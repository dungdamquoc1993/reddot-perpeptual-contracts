pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "../src/oracle/PriceFeed.sol";
import "./mocks/MockAggregator.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PriceFeedTest is Test {
    PriceFeed priceFeed;
    MockAggregator aggregator;
    address owner = 0x9Cb2f2c0122a1A8C90f667D1a55E5B45AC8b6086;
    address eve = 0x462beDFDAFD8681827bf8E91Ce27914cb00CcF83;
    address alice = 0xfC067b2BE205F8e8C85aC653f64C52baa225aCa4;
    address usdc;

    function setUp() external {
        aggregator = new MockAggregator();
        vm.prank(owner);
        priceFeed = new PriceFeed();
        usdc = address(new MockERC20("USDC", "USDC", 6));
    }

    function testSetTokenConfig() external {
        vm.prank(eve);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        priceFeed.configToken(usdc, address(priceFeed), 8);

        vm.prank(owner);
        vm.expectRevert(bytes("PriceFeed::invalidPriceFeed"));
        priceFeed.configToken(usdc, address(0), 8);

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit TokenAdded(usdc);
        priceFeed.configToken(usdc, address(aggregator), 8);

        (uint baseUnits, uint priceUnits, address chainlinkFeed) = priceFeed.tokenConfig(usdc);
        assertEq(baseUnits, 1e6);
        assertEq(priceUnits, 1e8);
        assertEq(chainlinkFeed, address(aggregator));
    }

    function testPostPrice() external {
        vm.prank(eve);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        priceFeed.addUpdater(alice);

        vm.prank(owner);
        priceFeed.addUpdater(alice);

        aggregator.setPrice(1e8);
        vm.prank(owner);
        priceFeed.configToken(usdc, address(aggregator), 8);

        vm.prank(eve);
        vm.expectRevert(bytes("PriceFeed::unauthorized"));
        priceFeed.postPrice(usdc, 1e8);

        vm.startPrank(alice);
        priceFeed.postPrice(usdc, 1e8);
        assertEq(priceFeed.getPrice(usdc), 1e24);

        vm.expectRevert(bytes("PriceFeed::priceGuarded"));
        priceFeed.postPrice(usdc, 5e8);
        assertEq(priceFeed.getPrice(usdc), 1e24);
    }

    event TokenAdded(address token);
}
