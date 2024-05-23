// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {MintableToken} from "../src/MintableToken.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract SyntheticV2 is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;
    AggregatorV3Interface internal dataFeed;

    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;
    uint64 subscriptionId;
    address public fetchData = address(this);

    error UnexpectedRequestID(bytes32 requestId);

    event Response(bytes32 indexed requestId, bytes response, bytes err);
    event TokensMinted(address indexed user, uint256 amount, address token);
    event TokensBurned(address indexed user, uint256 amount, address token);
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);

    address router = 0xC22a79eBA640940ABB6dF0f7982cc119578E11De;

    string source =
        "const ticker = args[0];"
        "const apiResponse = await Functions.makeHttpRequest({"
        "url: `https://chainlink-wine.vercel.app/api/alpha/${ticker}`"
        "});"
        "if (apiResponse.error) {"
        "throw Error('Request failed');"
        "}"
        "const { data } = apiResponse;"
        "const dataMultiplied = data * 100;"
        "return Functions.encodeUint256(dataMultiplied);";

    uint32 gasLimit = 300000;

    bytes32 donID =
        0x66756e2d706f6c79676f6e2d616d6f792d310000000000000000000000000000;

    uint256 public price;

    mapping(address => uint256) public depositedAmount;
    mapping(address => MintableToken) public syntheticTokens;
    mapping(address => address[]) public walletToContractAddresses;
    mapping(address => uint256) public userTokenBalances;

    uint256 public lastStockPrice;
    uint256 constant OVER_COLLATERALIZATION_RATIO = 2; // 200% over-collateral

    constructor(
        uint64 _subId
    ) FunctionsClient(router) ConfirmedOwner(msg.sender) {
        subscriptionId = _subId;
        dataFeed = AggregatorV3Interface(
            0x001382149eBa3441043c1c66972b4772963f5D43 // MATIC/USD price feed
        );
    }

    function getChainlinkDataFeedLatestAnswer() public view returns (int256) {
        (, int answer, , , ) = dataFeed.latestRoundData();
        return answer;
    }

    function sendRequest(
        string[] calldata args
    ) internal returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        if (args.length > 0) req.setArgs(args);

        s_lastRequestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );

        return s_lastRequestId;
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId);
        }

        s_lastResponse = response;
        price = convertBytesToUint(response);
        s_lastError = err;

        emit Response(requestId, s_lastResponse, s_lastError);
    }

    function convertBytesToUint(
        bytes memory response
    ) public pure returns (uint256) {
        return abi.decode(response, (uint256));
    }

    function depositAndMint(
        string memory _name,
        string memory _symbol,
        string[] calldata _stock
    ) external payable {
        require(msg.value > 0, "Insufficient deposit amount");
        depositedAmount[msg.sender] += msg.value;
        emit CollateralDeposited(msg.sender, msg.value);

        bytes32 stockPriceBytes32 = sendRequest(_stock);
        // We'll need to wait for Chainlink fulfillment, so handle this asynchronously
        // The rest of the function will assume price is fetched correctly and proceed
        fulfillMinting(msg.sender, _name, _symbol, stockPriceBytes32);
    }

    function fulfillMinting(
        address user,
        string memory _name,
        string memory _symbol,
        bytes32 stockPriceBytes32
    ) internal {
        uint256 stockPrice = bytesToUint(stockPriceBytes32);
        lastStockPrice = stockPrice;

        int256 ethPriceInUsd = getChainlinkDataFeedLatestAnswer();
        uint256 depositValueInUsd = (uint256(ethPriceInUsd) *
            depositedAmount[user]) / 1e18;
        uint256 maxMintableTokenValueInUsd = depositValueInUsd /
            OVER_COLLATERALIZATION_RATIO;
        uint256 tokensToMint = maxMintableTokenValueInUsd / uint256(stockPrice);

        MintableToken newToken = new MintableToken(
            _name,
            _symbol,
            tokensToMint
        );
        syntheticTokens[user] = newToken;
        newToken.mint(user, tokensToMint);
        userTokenBalances[user] = tokensToMint;

        walletToContractAddresses[user].push(address(newToken));

        emit TokensMinted(user, tokensToMint, address(newToken));
    }

    function redeemAndBurn(uint256 amountToBurn) external {
        require(
            syntheticTokens[msg.sender].balanceOf(msg.sender) >= amountToBurn,
            "Insufficient token balance"
        );

        uint256 totalSupply = syntheticTokens[msg.sender].totalSupply();
        uint256 redeemableAmount = (depositedAmount[msg.sender] *
            amountToBurn) / totalSupply;

        syntheticTokens[msg.sender].burn(msg.sender, amountToBurn);
        depositedAmount[msg.sender] -= redeemableAmount;
        userTokenBalances[msg.sender] -= amountToBurn;

        payable(msg.sender).transfer(redeemableAmount);

        emit TokensBurned(
            msg.sender,
            amountToBurn,
            address(syntheticTokens[msg.sender])
        );
        emit CollateralWithdrawn(msg.sender, redeemableAmount);
    }

    function bytesToUint(bytes32 _bytes) internal pure returns (uint256) {
        return uint256(_bytes);
    }

    // Getter Functions
    function getDepositedAmount(address user) external view returns (uint256) {
        return depositedAmount[user];
    }

    function getSyntheticTokenAddress(
        address user
    ) external view returns (address) {
        return address(syntheticTokens[user]);
    }

    function getUserTokenBalance(address user) external view returns (uint256) {
        return userTokenBalances[user];
    }

    function getWalletContractAddresses(
        address user
    ) external view returns (address[] memory) {
        return walletToContractAddresses[user];
    }
}
