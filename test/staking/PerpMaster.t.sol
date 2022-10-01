// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {PerpToken} from "../../src/assets/PerpToken.sol";
import {PerpMaster} from "../../src/staking/PerpMaster.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockRewarder} from "../mocks/MockRewarder.sol";

contract PerpMasterTest is Test {
    address owner = 0x9Cb2f2c0122a1A8C90f667D1a55E5B45AC8b6086;
    address eve = 0x462beDFDAFD8681827bf8E91Ce27914cb00CcF83;
    address alice = 0xfC067b2BE205F8e8C85aC653f64C52baa225aCa4;

    PerpToken perpToken;
    PerpMaster perpMaster;
    MockERC20 lpToken;
    MockRewarder mockRewarder;

    function setUp() external {
        vm.startPrank(owner);
        lpToken = new MockERC20("LpToken", "LpToken", 18);
        perpToken = new PerpToken();
        perpMaster = new PerpMaster();
        mockRewarder = new MockRewarder();
        perpToken.setMinter(address(perpMaster));
        perpMaster.setRewardMinter(address(perpToken));
        perpMaster.setRewardPerSecond(1e16);
        vm.stopPrank();
        vm.startPrank(alice);
        lpToken.mint(10e18);
        lpToken.approve(address(perpMaster), 10e18);
        vm.stopPrank();
        vm.deal(eve, 100e18);
    }

    function testPoolLength() external {
        vm.startPrank(owner);
        perpMaster.add(10, lpToken, mockRewarder);
        assertEq(perpMaster.poolLength(), 1);
    }

    function testDeposit() external {
        vm.prank(owner);
        perpMaster.add(10, lpToken, mockRewarder);
        vm.startPrank(alice);
        lpToken.approve(address(perpMaster), 10e18);
        perpMaster.deposit(0, 1e18, alice);
    }

    function testFailDeposiNonExistentPool() external {
        vm.prank(owner);
        perpMaster.add(10, lpToken, mockRewarder);
        vm.startPrank(alice);
        lpToken.approve(address(perpMaster), 10e18);
        perpMaster.deposit(1, 1e18, alice);
    }

    function testPendingRewardShouldEqualReward() external {
        vm.prank(owner);
        perpMaster.add(10, lpToken, mockRewarder);
        vm.startPrank(alice);
        lpToken.approve(address(perpMaster), 10e18);
        perpMaster.deposit(0, 1e18, alice);
        vm.stopPrank();
        vm.warp(60);
        vm.roll(2);
        uint256 expectedReward = 1e16 * 59;
        uint256 pendingReward = perpMaster.pendingReward(0, alice);
        assertEq(expectedReward, pendingReward);
    }

    function testHarvestReward() external {
        vm.prank(owner);
        perpMaster.add(10, lpToken, mockRewarder);
        vm.startPrank(alice);
        lpToken.approve(address(perpMaster), 10e18);
        perpMaster.deposit(0, 1e18, alice);
        vm.warp(60);
        uint256 expectedReward = 1e16 * 59;
        perpMaster.withdraw(0, 1e18, alice);
        perpMaster.harvest(0, alice);
        assertEq(perpToken.balanceOf(alice), expectedReward);
        vm.stopPrank();
    }
}
