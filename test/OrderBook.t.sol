// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {OrderBook} from "../src/orders/OrderBook.sol";
import {OrderType, Order, IModule} from "../src/interfaces/IOrderBook.sol";
import {Side} from "../src/interfaces/IPositionManager.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {WETH9Mock} from "./mocks/WETH9Mock.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {ILPToken} from "../src/interfaces/ILPToken.sol";
import {LimitOrderModule} from "../src/orders/LimitOrderModule.sol";
import {MarketOrderModule} from "../src/orders/MarketOrderModule.sol";
import {Vault} from "../src/Vault.sol";

contract TestOrderBook is OrderBook {
    function getOrder(bytes32 key) external returns (Order memory) {
        return orders[key];
    }
}

contract OrderBookTest is Test {
    TestOrderBook orderBook;
    MockOracle oracle;
    address owner = 0x9Cb2f2c0122a1A8C90f667D1a55E5B45AC8b6086;
    address user1 = 0x462beDFDAFD8681827bf8E91Ce27914cb00CcF83;
    address user2 = 0xfC067b2BE205F8e8C85aC653f64C52baa225aCa4;
    address userExecutor = 0x1FC04c07d3e342D6EC97f257B3f41465d1B03eC2;
    address positionManager;
    MockERC20 bnb;
    MockERC20 usdc;
    WETH9Mock weth;
    IModule limitOrder;
    IModule marketOrder;

    function setUp() public {
        vm.startPrank(owner);
        oracle = new MockOracle();
        weth = new WETH9Mock();
        usdc = new MockERC20("USDC", "Usdc", 6);
        bnb = new MockERC20("BNB", "BNB", 18);
        oracle.setPrice(address(bnb), 200e6);
        oracle.setPrice(address(weth), 1000e6);

        // instantiate to get address
        // We dont actually call vault function, just mock it.
        // However mock call function sometime does NOT work with address without code
        positionManager = address(new Vault());

        orderBook = new TestOrderBook();
        orderBook.initialize(positionManager, address(oracle), 3e14);
        limitOrder = IModule(new LimitOrderModule());
        marketOrder = IModule(new MarketOrderModule(100));
        orderBook.supportModule(address(limitOrder));
        orderBook.supportModule(address(marketOrder));
        vm.stopPrank();

        vm.prank(user1);
        bnb.mint(4e18);
        vm.prank(user2);
        bnb.mint(4e18);
        vm.deal(user1, 10e18);
    }

    function testPlaceIncreasementMarketOrder() public {
        vm.mockCall(positionManager, abi.encodeWithSelector(IPositionManager.validateToken.selector), abi.encode(true));
        vm.startPrank(user1);
        bnb.approve(address(orderBook), 1e18);
        bytes memory auxData = abi.encode(uint256(200e6)); // acceptable price
        bytes memory data = abi.encode(address(0), uint256(0), 200e6, auxData);
        // vm.recordLogs();
        vm.roll(1);
        vm.warp(100);
        bytes32 key = orderBook.placeOrder{value: 4e14}(
            marketOrder,
            address(bnb),
            address(bnb),
            Side.LONG,
            OrderType.INCREASE,
            1e18,
            data
        );

        assertFalse(key == bytes32(0));
        Order memory order = orderBook.getOrder(key);
        assertEq(order.owner, user1);
        assertEq(address(order.module), address(marketOrder));

        // cannot execute in the same block
        vm.expectRevert(bytes("OrderBook: excute order failed: Block not pass"));
        orderBook.executeOrder(key, payable(user2));

        // cannot execute when order too old
        vm.roll(2);
        vm.warp(300);
        vm.expectRevert(bytes("OrderBook: excute order failed: MarketOrderModule: order timed out"));
        orderBook.executeOrder(key, payable(user2));

        // cannot execute when price move too fast
        vm.warp(120);
        vm.mockCall(positionManager, abi.encodeWithSelector(IPositionManager.increasePosition.selector), bytes(""));
        oracle.setPrice(address(bnb), 201e6);
        vm.expectRevert(bytes("OrderBook: excute order failed: MarketOrderModule: mark price higher than limit"));
        orderBook.executeOrder(key, payable(user2));

        // executed and pay fee
        vm.roll(3);
        uint256 user2Balance = user2.balance;
        oracle.setPrice(address(bnb), 199e6);
        orderBook.executeOrder(key, payable(user2));
        uint256 feeReceived = user2.balance - user2Balance;
        assertEq(feeReceived, 4e14);
    }
}
