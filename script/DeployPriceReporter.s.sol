// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/utils/PriceReporter.sol";

contract DeployPriceReporterScript is Script {
    function run() public {
        address oracle = 0xCB7F3eF0801923fcd288dDb03fB42EcB042e8c56;
        address orderBook = 0xBc9B15346A7285Ef1AF1d89F0BFC075B40EDF45F;
        vm.startBroadcast();
        new PriceReporter(oracle, orderBook);
        vm.stopBroadcast();
    }
}
