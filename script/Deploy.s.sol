// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {Synthetic} from "../src/Synthetic.sol";
import {console2} from "forge-std/console2.sol";

contract DeployScript is Script {
    //string constant mintSource = "./functions/sources/stockPriceSource.js";
    uint64 constant subId = 194;
    address router = 0xC22a79eBA640940ABB6dF0f7982cc119578E11De;
    uint32 constant gasLimit = 300000;
    bytes32 constant donID =
        0x66756e2d706f6c79676f6e2d616d6f792d310000000000000000000000000000;

    function run() external {
        vm.startBroadcast();
        Synthetic synthetic = new Synthetic(subId, router, gasLimit, donID);
        vm.stopBroadcast();
        console2.log("Synthetic contract deployed to:", address(synthetic));
    }
}
