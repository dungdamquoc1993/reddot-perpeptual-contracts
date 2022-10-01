// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {AssetManager} from "../src/assets/AssetManager.sol";
import {LPToken} from "../src/assets/LPToken.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {ILPToken} from "../src/interfaces/ILPToken.sol";

// create an concrete contract to instantiate since AssetManager is abstract
contract Testable is AssetManager {
    function initialize(address lpToken, address stableCoin) external {
        AssetManager__initialize(lpToken, stableCoin);
    }
}

contract AssetManagerTest is Test {
    Testable liqMan;
    MockOracle oracle;
    address owner = 0x9Cb2f2c0122a1A8C90f667D1a55E5B45AC8b6086;
    address eve = 0x462beDFDAFD8681827bf8E91Ce27914cb00CcF83;
    address alice = 0xfC067b2BE205F8e8C85aC653f64C52baa225aCa4;
    LPToken lpToken;
    MockERC20 usdc;
    MockERC20 wbtc;

    function setUp() public {
        vm.startPrank(owner);
        oracle = new MockOracle();
        lpToken = new LPToken();
        liqMan = new Testable();
        liqMan.setOracle(address(oracle));
        lpToken.setMinter(address(liqMan));
        usdc = new MockERC20("USDC", "USDC", 6);
        wbtc = new MockERC20("WBTC", "WBTC", 8);
        liqMan.initialize(address(lpToken), address(usdc));
        vm.stopPrank();
        vm.prank(alice);
        usdc.mint(1000e6);
        vm.prank(eve);
        usdc.mint(1000e6);
        vm.deal(alice, 100e18);
        vm.deal(eve, 100e18);
    }

    function testFailSetOracleFromWildAddress() public {
        vm.prank(eve);
        liqMan.setOracle(address(oracle));
    }

    function testSetOracle() public {
        vm.prank(owner);
        liqMan.setOracle(address(oracle));
    }

    function testFailToAddLiquidityWhenPriceNotAvailable() public {
        vm.prank(owner);
        liqMan.addToken(address(wbtc));
        vm.startPrank(alice, alice);
        wbtc.approve(address(liqMan), 1000e6);
        liqMan.addLiquidity(address(wbtc), 100e6, 0, alice);
    }

    function testFailToAddLiquidityUsingNotWhitelistedToken() public {
        vm.startPrank(alice, alice);
        wbtc.approve(address(liqMan), 1000e6);
        vm.expectRevert();
        liqMan.addLiquidity(address(wbtc), 100e6, 0, alice);
    }

    function testAddLiquidity() public {
        vm.prank(owner);
        oracle.setPrice(address(usdc), 1e18);
        uint256 amountOut = _addLiquidity(alice, 100e6);
        assertEq(amountOut, 100e18);
        assertEq(liqMan.getPoolValue(), 100e24);
    }

    function testRemoveLiquidity() public {
        vm.prank(owner);
        oracle.setPrice(address(usdc), 1e18);
        _addLiquidity(alice, 100e6);

        uint256 usdcBalance = usdc.balanceOf(alice);
        vm.startPrank(alice);
        lpToken.approve(address(liqMan), 10e18);
        liqMan.removeLiquidity(address(usdc), 10e18, 0, alice);
        uint256 amountOut = usdc.balanceOf(alice) - usdcBalance;
        assertEq(amountOut, 10e6);
    }

    function _addLiquidity(address from, uint256 amount) internal returns (uint256) {
        vm.startPrank(from);
        usdc.mint(amount);
        uint256 lpBalance = lpToken.balanceOf(alice);
        usdc.approve(address(liqMan), amount);
        liqMan.addLiquidity(address(usdc), amount, 0, alice);
        vm.stopPrank();
        return lpToken.balanceOf(alice) - lpBalance;
    }
}
