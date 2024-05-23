// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {MintableToken} from "../src/MintableToken.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Synthetic is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;
    AggregatorV3Interface internal dataFeed;

    // State variables to store the last request ID, response, and error
    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;
    uint64 subscriptionId;
    address public fetchData = address(this);
    // Custom error type
    error UnexpectedRequestID(bytes32 requestId);

    // Event to log responses
    event Response(
        bytes32 indexed requestId,
        string character,
        bytes response,
        bytes err
    );

    // event TokensMinted(address indexed minter, uint256 totalMintedTokens);
    event TokensMinted(address indexed user, uint256 amount, address token);

    address router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;

    // JavaScript source code
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

    //Callback gas limit
    uint32 gasLimit = 300000;

    bytes32 donID =
        hex"66756e2d706f6c79676f6e2d616d6f792d310000000000000000000000000000";

    // State variable to store the returned character information
    uint256 public price;

    mapping(address => uint256) public depositedAmount;
    mapping(address => MintableToken) public syntheticTokens;
    mapping(address => address[]) public walletToContractAddresses;
    // uint256 public constant DEPOSIT_AMOUNT = 1 ether;
    uint256 public lastStockPrice;
    uint256 constant OVER_COLLATERALIZATION_RATIO = 2; // 200% over-collateral

    constructor(
        uint64 _subId
    ) FunctionsClient(router) ConfirmedOwner(msg.sender) {
        subscriptionId = _subId;
        dataFeed = AggregatorV3Interface(
            0x694AA1769357215DE4FAC081bf1f309aDC325306
        );
    }

    function getChainlinkDataFeedLatestAnswer() public view returns (int256) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return answer;
    }

    function sendRequest(
        string[] calldata args
    ) internal returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source); // Initialize the request with JS code
        if (args.length > 0) req.setArgs(args); // Set the arguments for the request

        // Send the request and store the request ID
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
            revert UnexpectedRequestID(requestId); // Check if request IDs match
        }

        s_lastResponse = response;
        price = convertBytesToUint(response);
        s_lastError = err;

        // Emit an event to log the response
        // emit Response(requestId, price, s_lastResponse, s_lastError);
    }

    function convertBytesToUint(
        bytes memory response
    ) public pure returns (uint256) {
        uint256 newprice = abi.decode(response, (uint256));
        return newprice;
    }

    function bytesToUint(bytes32 _bytes) internal pure returns (uint256) {
        return uint256(_bytes);
    }

    uint256 public depositValue;

    function depositAndMint(
        // uint256 amountToMint,
        string memory _name,
        string memory _symbol,
        string[] calldata _stock
    ) external payable {
        //fetch stock price
        bytes32 stockPriceBytes32 = sendRequest(_stock);
        uint256 stockPrice = bytesToUint(stockPriceBytes32);
        lastStockPrice = stockPrice;

        //fetch the price of eth in usd???? using chainlink price feeds
        int256 ethPriceInUsd = getChainlinkDataFeedLatestAnswer() * 1e10;
        require(msg.value > 0, "Insufficient deposit amount");
        depositedAmount[msg.sender] += msg.value;
        uint256 depositValueInUsd = (uint256(ethPriceInUsd) * msg.value) / 1e18;
        depositValue = depositValueInUsd;
        // Calculate the maximum mintable token value based on the over-collateralization ratio
        uint256 maxMintableTokenValueInUsd = depositValueInUsd /
            OVER_COLLATERALIZATION_RATIO;
        // Calculate the number of tokens to mint based on the stock price
        uint256 tokensToMint = maxMintableTokenValueInUsd / uint256(stockPrice);

        MintableToken newToken = new MintableToken(
            _name,
            _symbol,
            tokensToMint
        );
        syntheticTokens[msg.sender] = newToken;
        newToken.mint(msg.sender, tokensToMint);

        //store minted tokens to address mapping
        walletToContractAddresses[msg.sender].push(address(newToken));
        //emit an event for total minted tokens to address
        emit TokensMinted(msg.sender, tokensToMint, address(newToken));
    }

    // function redeemAndBurn(uint256 amountToBurn) external {
    //     require(
    //         syntheticTokens[msg.sender].balanceOf(msg.sender) >= amountToBurn,
    //         "Insufficient token balance"
    //     );
    //     syntheticTokens[msg.sender].burn(msg.sender, amountToBurn);
    //     uint256 redeemAmount = (amountToBurn * DEPOSIT_AMOUNT) /
    //         syntheticTokens[msg.sender].totalSupply();
    //     depositedAmount[msg.sender] -= redeemAmount;
    //     payable(msg.sender).transfer(redeemAmount);
    // }
}
