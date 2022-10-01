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

contract Deploy is Script {
    MockERC20 usdc;
    MockERC20 wbtc;
    MockERC20 weth;
    PriceFeed oracle;
    Vault vault;
    OrderBook orderBook;
    LPToken lpToken;

    function run() external {
        vm.startBroadcast();
        deployMockTokens();
        deployOracle();
        orderBook = new OrderBook();
        deployVault();
        initOrderBook();
        vm.stopBroadcast();
    }

    function deployMockTokens() internal {
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        wbtc = new MockERC20("Mock WBTC", "mWBTC", 8);
        weth = new MockERC20("Mock WETH", "mWETH", 18);
    }

    function deployOracle() internal {
        oracle = new PriceFeed();
        address BTC_USD = 0x007A22900a3B98143368Bd5906f8E17e9867581b;
        address USDC_USD = 0x572dDec9087154dC5dfBB1546Bb62713147e0Ab0;
        address ETH_USD = 0x0715A7794a1dc8e42615F059dD6e406A6594651A;
        address MATIC_USD = 0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada;

        oracle.configToken(address(usdc), USDC_USD, 8);
        oracle.configToken(address(wbtc), BTC_USD, 8);
        oracle.configToken(address(weth), ETH_USD, 8);
        oracle.configToken(address(UniERC20.ETH), MATIC_USD, 8);
    }

    function initOrderBook() internal {
        orderBook.initialize(address(vault), address(oracle), 3e14);
        IModule limitOrder = IModule(new LimitOrderModule());
        IModule marketOrder = IModule(new MarketOrderModule(5 * 60));
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

        vault.setOrderBook(address(orderBook));
        vault.setOracle(address(oracle));
        lpToken.setMinter(address(vault));
        vault.addToken(UniERC20.ETH);
        vault.addToken(address(wbtc));
        vault.addToken(address(weth));
    }
}
