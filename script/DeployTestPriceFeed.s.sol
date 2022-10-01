// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/oracle/TestPriceFeed.sol";

contract DeployTestPriceFeedScript is Script {
    function run() public {
        vm.startBroadcast();
        TestPriceFeed oracle = new TestPriceFeed();

        address mUSDC = 0xc2D1d0492A5C9AC735e5Fa08Eb9376f850222ebF;
        address mWBTC = 0x4FC502C8Ac409D21F62B39b40Ad632D4352a0301;
        address mWETH = 0x22ef18332eeE60E55274341a2fa4B726C71046CF;

        oracle.configToken(mUSDC, 8);
        oracle.configToken(mWBTC, 8);
        oracle.configToken(mWETH, 8);
        oracle.configToken(UniERC20.ETH, 8);

        vm.stopBroadcast();
    }
}
