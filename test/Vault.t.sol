// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {ILPToken} from "../src/interfaces/ILPToken.sol";
import {Side} from "../src/interfaces/IPositionManager.sol";
import {LPToken} from "../src/assets/LPToken.sol";
import {PoolAsset} from "../src/assets/PoolAsset.sol";
import {UniERC20} from "../src/lib/UniERC20.sol";

contract VaultTest is Test {
    Vault vault;
    address owner = 0x2E20CFb2f7f98Eb5c9FD31Df41620872C0aef524;
    address orderBook = 0x69D4aDe841175fE72642D03D82417215D4f47790;
    address alice = 0xfC067b2BE205F8e8C85aC653f64C52baa225aCa4;
    address bob = 0x90FbB788b18241a4bBAb4cd5eb839a42FF59D235;
    LPToken lpToken;
    MockERC20 btc;
    MockERC20 usdc;
    MockOracle oracle;

    function setUp() external {
        vm.startPrank(owner);
        btc = new MockERC20("WBTC", "WBTC", 8);
        usdc = new MockERC20("USDC", "USDC", 6);
        lpToken = new LPToken();
        oracle = new MockOracle();
        vault = new Vault();
        vault.initialize(
            address(lpToken),
            address(usdc),
            1e7, // poition fee
            1e7, // liquidation fee
            1e9, // admin fee
            1e6, // interest rate (funding rate)
            100 //
        );
        vault.setOrderBook(orderBook);
        vault.setOracle(address(oracle));
        lpToken.setMinter(address(vault));
        vault.addToken(UniERC20.ETH);
        vault.addToken(address(btc));
        vm.stopPrank();
    }

    function testAddAndRemoveLiquidity() external {
        oracle.setPrice(address(usdc), 1e18);
        oracle.setPrice(address(btc), 20000e16);
        oracle.setPrice(UniERC20.ETH, 1000e6);
        vm.startPrank(alice);
        vm.deal(alice, 100e18);
        btc.mint(1e8);
        usdc.mint(10000e6);
        btc.approve(address(vault), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);

        // // add more 10k $
        vault.addLiquidity(address(usdc), 10000e6, 0, address(alice));
        {
            (uint256 poolAmount, , , , , , uint256 poolBalance) = vault.poolAssets(address(usdc));
            assertEq(poolBalance, 10000e6);
            assertEq(poolAmount, 10000e6);
            assertEq(lpToken.balanceOf(address(alice)), 10000e18);
            assertEq(vault.getPoolValue(), 10000e24);
        }

        // add 1btc = 20k$, receive 20k LP
        vault.addLiquidity(address(btc), 1e8, 0, address(alice));
        assertEq(lpToken.balanceOf(address(alice)), 30000e18);
        {
            (uint256 poolAmount, uint256 reserve, uint256 feeReserve, , , , uint256 poolBalance) = vault.poolAssets(
                address(btc)
            );
            assertEq(poolBalance, 1e8);
            assertEq(poolAmount, 1e8);
            assertEq(feeReserve, 0);
            assertEq(reserve, 0);
            // console.log(vault.getPoolValue());
            assertEq(vault.getPoolValue(), 30000e24);
        }

        // eth
        vault.addLiquidity{value: 10e18}(UniERC20.ETH, 10e18, 0, address(alice));
        assertEq(vault.getPoolValue(), 40000e24);
        assertEq(lpToken.balanceOf(address(alice)), 40000e18);

        lpToken.approve(address(vault), type(uint256).max);
        vault.removeLiquidity(address(usdc), 1e18, 0, alice);
        assertEq(usdc.balanceOf(alice), 1e6);
        vm.stopPrank();
    }

    function testOnlyOrderBookCanIncreaseDecreasePosition() external {
        vm.expectRevert(bytes("PositionManager: only orderbook allowed"));
        vault.increasePosition(alice, address(btc), 1e8, Side.LONG);
        vm.expectRevert(bytes("PositionManager: only orderbook allowed"));
        vault.decreasePosition(alice, address(btc), 1e6, 1e8, Side.LONG);
    }

    function testSetOrderBook() external {
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setOrderBook(alice);
        vm.prank(owner);
        vault.setOrderBook(alice);
        assertEq(vault.orderBook(), alice);
    }

    function _beforeTestPosition() internal {
        vm.prank(owner);
        vault.setOrderBook(orderBook);
        oracle.setPrice(address(usdc), 1e18);
        oracle.setPrice(address(btc), 20000e16);
        oracle.setPrice(UniERC20.ETH, 1000e6);
        vm.startPrank(alice);
        btc.mint(1e8);
        usdc.mint(10000e6);
        vm.deal(alice, 1e18);
        vm.stopPrank();
    }

    function testCannotLongWithInvalidSize() external {
        _beforeTestPosition();

        vm.startPrank(orderBook);
        btc.mint(1e8);

        // cannot open position with size larger than pool amount
        btc.transfer(address(vault), 1e7); // 0.1BTC = 2_000$
        // try to long 10x
        vm.expectRevert(bytes("PoolAsset: reserve exceed pool amount"));
        vault.increasePosition(alice, address(btc), 20_000e24, Side.LONG);
        vm.stopPrank();
    }

    function testLongPosition() external {
        _beforeTestPosition();
        // add liquidity
        vm.startPrank(alice);
        btc.approve(address(vault), type(uint256).max);
        vault.addLiquidity(address(btc), 1e8, 0, alice);
        vm.stopPrank();

        vm.startPrank(orderBook);
        btc.mint(1e8);
        btc.transfer(address(vault), 1e7); // 0.1BTC = 2_000$

        // try to open long position with 5x leverage
        vm.warp(1000);
        vault.increasePosition(alice, address(btc), 10_000e24, Side.LONG);
        Vault.PositionView memory position = vault.getPosition(alice, address(btc), Side.LONG);
        assertEq(position.size, 10_000e24);
        assertEq(position.reserveAmount, 5e7);
        assertEq(position.collateralValue, 1990e24); // 0.1% fee = 2000 - (20_000 * 0.1%) = 1990

        {
            (, , , , , uint256 lastAccrualTimestamp, uint256 cumulativeInterestRate) = vault.fee();
            assertEq(lastAccrualTimestamp, 1000);
            assertEq(cumulativeInterestRate, 0);
        }

        {
            // check pool value
            uint256 poolValue = vault.getPoolValue();
            console.log("poolValue", poolValue);
        }

        {
            // guaranteed value = total size - total collateral = 10_000 - 1990 = 8_010
            (
                uint256 poolAmount,
                uint256 reservedAmount,
                uint256 feeReserve,
                uint256 guaranteedValue,
                ,
                ,
                uint256 poolBalance
            ) = vault.poolAssets(address(btc));
            assertEq(poolBalance, 110000000); // 1BTC deposit + 0.1BTC collateral
            assertEq(poolAmount + feeReserve, poolBalance);
            assertEq(reservedAmount, 5e7); // 0.5BTC = position size
            assertEq(guaranteedValue, 8_010e24);
        }

        // calculate pnl
        oracle.setPrice(address(btc), 20_500e16);
        position = vault.getPosition(alice, address(btc), Side.LONG);
        assertEq(position.pnl, 250e24);

        {
            // check pool value
            uint256 poolValue = vault.getPoolValue();
            console.log("poolValue", poolValue);
        }

        vm.warp(1100);
        uint256 priorBalance = btc.balanceOf(alice);
        // close 50%, fee = 5 (position) + 1 (funding/interest)
        // profit = 125, transfer out 995$ + 119$ = 0.05434146BTC
        vault.decreasePosition(alice, address(btc), 0, 5_000e24, Side.LONG);

        {
            (, , , , , uint256 lastAccrualTimestamp, uint256 cumulativeInterestRate) = vault.fee();
            assertEq(lastAccrualTimestamp, 1100);
            assertEq(cumulativeInterestRate, 1e6); // 1 interval
        }
        position = vault.getPosition(alice, address(btc), Side.LONG);
        assertEq(position.size, 5_000e24);
        assertEq(position.collateralValue, 995e24);
        {
            uint256 balance = btc.balanceOf(alice);
            uint256 transferOut = balance - priorBalance;
            assertEq(transferOut, 5434146);
            priorBalance = balance;
        }

        {
            (uint256 poolAmount, uint256 reservedAmount, uint256 feeReserve, , , , uint256 poolBalance) = vault
                .poolAssets(address(btc));
            assertEq(reservedAmount, 25e6);
            assertEq(poolBalance, 104565854);
            assertEq(poolAmount + feeReserve, poolBalance);
        }

        {
            // check pool value
            uint256 poolValue = vault.getPoolValue();
            console.log("poolValue", poolValue);
        }

        // close full
        vm.warp(1200);
        vault.decreasePosition(alice, address(btc), 0, 5_000e24, Side.LONG);

        position = vault.getPosition(alice, address(btc), Side.LONG);
        assertEq(position.size, 0);
        assertEq(position.collateralValue, 0);
        {
            uint256 balance = btc.balanceOf(alice);
            uint256 transferOut = balance - priorBalance;
            assertEq(transferOut, 5436585);
            priorBalance = balance;
        }

        {
            // check pool value
            uint256 poolValue = vault.getPoolValue();
            console.log("poolValue", poolValue);
        }
        vm.stopPrank();
    }

    function testShortPosition() external {
        _beforeTestPosition();
        // add liquidity
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.addLiquidity(address(usdc), 10000e6, 0, alice);
        vm.stopPrank();

        vm.startPrank(orderBook);
        // try to open long position with 5x leverage
        usdc.mint(2000e6);
        usdc.transfer(address(vault), 2000e6); // 0.1BTC = 2_000$
        vm.warp(1000);
        vault.increasePosition(alice, address(btc), 10_000e24, Side.SHORT);

        {
            Vault.PositionView memory position = vault.getPosition(alice, address(btc), Side.SHORT);
            assertEq(position.size, 10_000e24);
            assertEq(position.collateralValue, 1990e24);
            assertEq(position.reserveAmount, 5e7);
        }

        {
            // check pool value
            uint256 poolValue = vault.getPoolValue();
            console.log("poolValue", poolValue);
        }

        {
            (, , , , uint256 totalShortSize, uint256 averageShortPrice, ) = vault.poolAssets(address(btc));
            assertEq(totalShortSize, 10_000e24);
            assertEq(averageShortPrice, 20_000e16);
        }

        {
            (, , , , , , uint256 poolBalance) = vault.poolAssets(address(usdc));
            assertEq(poolBalance, 12000e6);
        }

        oracle.setPrice(address(btc), 19500e16);
        {
            Vault.PositionView memory position = vault.getPosition(alice, address(btc), Side.SHORT);
            console.log("PnL", position.pnl);
            console.log("reserve", position.reserveAmount);
        }

        vm.warp(1100);
        uint256 priorBalance = usdc.balanceOf(alice);
        vault.decreasePosition(alice, address(btc), 0, 10_000e24, Side.SHORT);
        uint256 transferOut = usdc.balanceOf(alice) - priorBalance;
        console.log("transfer out", transferOut);

        {
            Vault.PositionView memory position = vault.getPosition(alice, address(btc), Side.SHORT);
            assertEq(position.size, 0);
            assertEq(position.collateralValue, 0);
        }
    }
}
