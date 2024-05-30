// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {MintableToken} from "../src/MintableToken.sol";
import {OracleLib, AggregatorV3Interface} from "../src/OracleLib.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Synthetic is
    FunctionsClient,
    ConfirmedOwner,
    AutomationCompatibleInterface,
    ReentrancyGuard
{
    using FunctionsRequest for FunctionsRequest.Request;
    AggregatorV3Interface internal dataFeed;

    // ***************************************************************
    // ********************** STATE VARS *****************************
    // ***************************************************************

    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;
    uint64 public subscriptionId;
    uint256 public stockPrice;
    uint256 public maxMintableTokenValueInUsd;
    string public newStockName;
    string public newStockSymbol;

    // Test vars
    uint256 public depositValue;
    uint256 public maxMintableTokenValueInUsdTest;
    uint256 public NoOFTokensToMint;
    int256 public ethPriceInUsd;
    address public user;
    bool public isNeeded = false;

    // Redemption vars
    mapping(bytes32 => address) public redeemRequests;

    // Custom error type
    error UnexpectedRequestID(bytes32 requestId);

    // ***************************************************************
    // ************************** EVENTS *****************************
    // ***************************************************************
    // Event to log responses
    event Response(
        bytes32 indexed requestId,
        string character,
        bytes response,
        bytes err
    );

    event Testresponse(
        address indexed user,
        string indexed stockName,
        string indexed stockSymbol,
        uint256 NoOFTokensToMint
    );

    event TokensMinted(address indexed user, uint256 amount, address token);
    event RequestFulfilled(
        address user,
        string stockName,
        string stockSymbol,
        uint256 tokensToMint
    );

    event DebugLog(string message);
    event DebugUint(string message, uint256 value);
    event DebugBytes(string message, bytes value);

    // address router = 0xC22a79eBA640940ABB6dF0f7982cc119578E11De; //amoy network
    address router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0; //sepolia network
    // address router = 0x234a5fb5Bd614a7AA2FfAB244D603abFA0Ac5C5C; // arb-sepolia

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

    // Callback gas limit
    uint32 public gasLimit = 300000;

    bytes32 public donID =
        0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000; // sepolia network
    //0x66756e2d706f6c79676f6e2d616d6f792d310000000000000000000000000000; // amoy network
    // 0x66756e2d617262697472756d2d7365706f6c69612d3100000000000000000000; //arb-sepolia

    mapping(address => uint256) public depositedAmount;
    mapping(address => MintableToken) public syntheticTokens;
    mapping(address => address[]) public walletToContractAddresses;

    constructor(
        uint64 _subId
    ) FunctionsClient(router) ConfirmedOwner(msg.sender) {
        subscriptionId = _subId;
        dataFeed = AggregatorV3Interface(
            0x694AA1769357215DE4FAC081bf1f309aDC325306 // sepolia network
            // 0xF0d50568e3A7e8259E16663972b11910F89BD8e7// eth/usd amoy network
            //0x001382149eBa3441043c1c66972b4772963f5D43 // matic/usd amoy network
            // 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165 // arb-sepolia eth/usd
        );
    }

    // ***************************************************************
    // ************************** DATAFEED  **************************
    // ***************************************************************

    function getChainlinkDataFeedLatestAnswer() public view returns (int256) {
        (
            ,
            /* uint80 roundID */ int answer /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
            ,
            ,

        ) = dataFeed.latestRoundData();
        return answer;
    }

    // ***************************************************************
    // ******************* CUSTOM AUTOMATION *************************
    // ***************************************************************

    function checkUpkeep(
        bytes calldata
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        upkeepNeeded = isNeeded;
    }

    function performUpkeep(bytes calldata /*performData*/) external override {
        mintStockTokens(newStockName, newStockSymbol, NoOFTokensToMint, user);
        isNeeded = false;
    }

    // ***************************************************************
    // ******************* CHAINLINK FUNCTIONS  **********************
    // ***************************************************************

    function sendRequest(
        string[] memory args
    ) internal returns (bytes32 requestId) {
        emit DebugLog("Sending request...");
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        if (args.length > 0) req.setArgs(args);
        s_lastRequestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );
        emit DebugBytes("Request ID", bytes32ToBytes(s_lastRequestId));

        return s_lastRequestId;
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        emit DebugLog("Fulfilling request...");
        if (s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId);
        }

        s_lastResponse = response;
        if (response.length == 0) {
            emit DebugLog("Empty response");
            s_lastError = err;
            return;
        }

        uint256 newPrice;
        try this.convertBytesToUint(response) returns (uint256 price) {
            newPrice = price;
        } catch (bytes memory err) {
            emit DebugLog("Failed to decode response");
            s_lastError = err;
            return;
        }

        stockPrice = newPrice * 1e16;
        s_lastError = err;

        // Check if it's a redeem request
        address redeemer = redeemRequests[requestId];
        if (redeemer != address(0)) {
            completeRedemption(redeemer, newPrice);
            delete redeemRequests[requestId];
        } else {
            stockTokensToMint(ethPriceInUsd, stockPrice);
            isNeeded = true;
            emit Testresponse(
                user,
                newStockName,
                newStockSymbol,
                NoOFTokensToMint
            );
        }

        emit DebugBytes("Fulfill Response", response);
        emit DebugBytes("Fulfill Error", err);
    }

    // ***************************************************************
    // *************** MAIN DEPOSIT AND MINT FUNCTION ****************
    // ***************************************************************

    function depositAndMint(
        string memory _name,
        string memory _symbol,
        string[] calldata _stock,
        address _user
    ) external payable nonReentrant {
        emit DebugLog("Depositing and minting...");
        require(msg.value > 0, "Insufficient deposit amount");
        depositedAmount[msg.sender] += msg.value;
        user = _user;
        newStockName = _name;
        newStockSymbol = _symbol;
        ethPriceInUsd = getChainlinkDataFeedLatestAnswer() * 1e10;
        uint256 depositValueInUsd = (uint256(ethPriceInUsd) * msg.value) / 1e18;
        depositValue = depositValueInUsd;
        emit DebugUint("Deposit Value in USD", depositValueInUsd);
        sendRequest(_stock);
    }

    function mintStockTokens(
        string memory _name,
        string memory _symbol,
        uint256 tokensToMint,
        address _user
    ) internal {
        emit DebugLog("Minting stock tokens...");
        MintableToken newToken = new MintableToken(
            _name,
            _symbol,
            tokensToMint,
            _user
        );
        syntheticTokens[_user] = newToken;

        walletToContractAddresses[_user].push(address(newToken));
        emit TokensMinted(_user, tokensToMint, address(newToken));
    }

    // ***************************************************************
    // ********************** REDEEM FUNCTION ************************
    // ***************************************************************

    function redeem(
        address _tokenAddress,
        uint256 _amountToRedeem,
        string memory _symbol
    ) public {
        MintableToken token = syntheticTokens[msg.sender];
        require(address(token) == _tokenAddress, "Invalid token address");

        // Ensure the user has enough tokens to redeem
        uint256 tokenBalance = token.balanceOf(msg.sender);
        require(tokenBalance >= _amountToRedeem, "Insufficient token balance");

        string[] memory symbols = new string[](1);
        symbols[0] = _symbol;

        // Send a request for the stock price and store the request ID
        bytes32 requestId = sendRequest(symbols);
        redeemRequests[requestId] = msg.sender;

        emit DebugLog("Redeem request sent");
    }

    function completeRedemption(address redeemer, uint256 newPrice) internal {
        MintableToken token = syntheticTokens[redeemer];

        // Get the user's token balance
        uint256 tokenBalance = token.balanceOf(redeemer);
        require(tokenBalance > 0, "No tokens to redeem");

        // Calculate the ETH amount to be redeemed based on the token amount
        uint256 ethAmount = (tokenBalance * newPrice) / 1e18;

        // Transfer the ETH to the user
        payable(redeemer).transfer(ethAmount);

        // Burn the specified amount of tokens
        token.burn(redeemer, tokenBalance);

        // If the user has no tokens left, remove the token contract from the mapping
        if (token.balanceOf(redeemer) == 0) {
            delete syntheticTokens[redeemer];
        }

        emit DebugLog("Redemption complete");
    }

    // ***************************************************************
    // ************************** HELPERS ****************************
    // ***************************************************************

    function convertBytesToUint(
        bytes memory response
    ) public pure returns (uint256) {
        return abi.decode(response, (uint256));
    }

    function stockTokensToMint(int256 _ethPrice, uint256 _stockPrice) internal {
        NoOFTokensToMint = (uint256(_ethPrice) / _stockPrice) / 2;
    }

    function bytes32ToBytes(bytes32 data) internal pure returns (bytes memory) {
        return abi.encodePacked(data);
    }

    // ***************************************************************
    // ***************** FOR TESTING TO RETRIEVE FUNDS****************
    // ***************************************************************
    function withdraw() public nonReentrant {
        payable(msg.sender).transfer(address(this).balance);
    }
}
