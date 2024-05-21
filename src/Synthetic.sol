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

    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;
    uint64 public subscriptionId;
    address public fetchData = address(this);
    error UnexpectedRequestID(bytes32 requestId);

    event Response(
        bytes32 indexed requestId,
        string price,
        bytes response,
        bytes err
    );
    event TokensMinted(address indexed user, uint256 amount, address token);

    address public router;
    string public source;
    uint32 public gasLimit;
    bytes32 public donID;
    string public price;

    mapping(address => uint256) public depositedAmount;
    mapping(address => MintableToken) public syntheticTokens;
    mapping(address => address[]) public walletToContractAddresses;
    uint256 public lastStockPrice;
    uint256 constant OVER_COLLATERALIZATION_RATIO = 2;

    constructor(
        uint64 _subId,
        address _router,
        string memory _source,
        uint32 _gasLimit,
        bytes32 _donID
    ) FunctionsClient(_router) ConfirmedOwner(msg.sender) {
        subscriptionId = _subId;
        router = _router;
        source = _source;
        gasLimit = _gasLimit;
        donID = _donID;
        dataFeed = AggregatorV3Interface(
            0xF0d50568e3A7e8259E16663972b11910F89BD8e7
        );
    }

    function getChainlinkDataFeedLatestAnswer() public view returns (int256) {
        (, int256 answer, , , ) = dataFeed.latestRoundData();
        return answer;
    }

    function sendRequest(
        string[] calldata args
    ) internal onlyOwner returns (bytes32 requestId) {
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
        price = string(response);
        s_lastError = err;

        emit Response(requestId, price, s_lastResponse, s_lastError);
    }

    function bytesToUint(bytes32 _bytes) internal pure returns (uint256) {
        return uint256(_bytes);
    }

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
        int256 ethPriceInUsd = getChainlinkDataFeedLatestAnswer();
        require(msg.value > 0, "Insufficient deposit amount");
        depositedAmount[msg.sender] += msg.value;
        uint256 depositValueInUsd = (uint256(ethPriceInUsd) * msg.value) / 1e18;
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

    function redeemAndBurn(uint256 amountToBurn) external {
        MintableToken token = syntheticTokens[msg.sender];
        require(
            address(token) != address(0),
            "No tokens minted for this address"
        );
        require(
            token.balanceOf(msg.sender) >= amountToBurn,
            "Insufficient token balance"
        );

        uint256 usdValueOfTokens = lastStockPrice * amountToBurn;
        int256 ethPriceInUsd = getChainlinkDataFeedLatestAnswer();
        uint256 ethValue = (usdValueOfTokens * 1e18) / uint256(ethPriceInUsd);

        token.burn(msg.sender, amountToBurn);

        require(
            depositedAmount[msg.sender] >= ethValue,
            "Insufficient deposited amount"
        );
        depositedAmount[msg.sender] -= ethValue;

        (bool success, ) = msg.sender.call{value: ethValue}("");
        require(success, "ETH transfer failed");
    }
}
