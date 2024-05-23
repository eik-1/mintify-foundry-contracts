// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/Synthetic.sol"; // Adjust the path based on your project structure

contract SyntheticTest is Test {
    Synthetic public synthetic;
    address public constant CONTRACT_ADDRESS =
        0x8242890FE87950952920eb4C96Bd2258375d9C2d;

    // Updateable values
    string public constant NAME = "Tesla";
    string public constant SYMBOL = "TSLA";
    string[] public STOCK = ["TSLA"];

    function setUp() public {
        // Deploy the contract (if needed) or attach to an existing contract
        synthetic = Synthetic(CONTRACT_ADDRESS);
    }

    function testDepositAndMint() public {
        // Set up the value to send with the transaction
        uint256 value = 0.001 ether;

        // Assume the user has enough ETH in their balance
        vm.deal(address(this), value);

        // Call the depositAndMint function
        synthetic.depositAndMint{value: value}(NAME, SYMBOL, STOCK);

        // Add assertions to verify the expected behavior
        // Example: check the balance of the minted tokens
        // MintableToken token = MintableToken(synthetic.syntheticTokens(address(this)));
        // uint256 balance = token.balanceOf(address(this));
        // assert(balance > 0);
    }
}
