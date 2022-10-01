// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../test/mocks/MockERC20.sol";
import "../src/Vault.sol";
import "../src/assets/LPToken.sol";
import "../src/oracle/PriceFeed.sol";
import "../src/orders/OrderBook.sol";
import "../src/orders/LimitOrderModule.sol";
import "../src/orders/MarketOrderModule.sol";
import "../src/lib/UniERC20.sol";

contract DeployVault is Script {
    address usdc = 0xc2D1d0492A5C9AC735e5Fa08Eb9376f850222ebF;
    address wbtc = 0x4FC502C8Ac409D21F62B39b40Ad632D4352a0301;
    address oracle = 0xCB7F3eF0801923fcd288dDb03fB42EcB042e8c56;
    OrderBook orderBook;
    Vault vault;
    LPToken lpToken;

    function run() external {
        vm.startBroadcast();
        orderBook = new OrderBook();
        deployVault();
        initOrderBook();
        vm.stopBroadcast();
    }

    function initOrderBook() internal {
        orderBook.initialize(address(vault), address(oracle), 3e14);
        address limitOrder = 0x84A993306FEDA24F768126e68C2A1213d2a8d95C;
        address marketOrder = 0x573F4494190F1b6a3F518daE8057aA2715f6900D;
        orderBook.supportModule(address(limitOrder));
        orderBook.supportModule(address(marketOrder));
    }

    function deployVault() internal {
        lpToken = new LPToken();
        vault = new Vault();
        vault.initialize(
            address(lpToken),
            address(usdc), // stable coin
            1e7, // poition fee
            1e7, // liquidation fee
            1e9, // admin fee
            5e6, // interest rate (funding rate, about 0.005%)
            1800 // funding interval
        );

        lpToken.setMinter(address(vault));
        vault.setOrderBook(address(orderBook));
        vault.setOracle(oracle);

        vault.addToken(UniERC20.ETH);
        vault.addToken(wbtc);
    }
}
