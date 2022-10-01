// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {IModule, OrderType, Order} from "../interfaces/IOrderBook.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {Side} from "../position/Position.sol";

contract MarketOrderModule is IModule {
    uint public maxOrderTimeout;

    constructor(uint _maxOrderTimeout) {
        require(_maxOrderTimeout > 0, "MarketOrderModule: invalid order timeout");
        maxOrderTimeout = _maxOrderTimeout;
    }

    /// @dev this function not restricted to view
    function execute(IOracle oracle, Order memory order) external view {
        uint256 acceptablePrice = abi.decode(order.data, (uint256));
        uint indexPrice = oracle.getPrice(order.indexToken);
        require(indexPrice > 0, "LimitOrderModule: invalid mark price");

        require(order.submissionTimestamp + maxOrderTimeout >= block.timestamp, "MarketOrderModule: order timed out");
        if (order.side == Side.LONG) {
            require(indexPrice <= acceptablePrice, "MarketOrderModule: mark price higher than limit");
        } else {
            require(indexPrice >= acceptablePrice, "MarketOrderModule: mark price lower than limit");
        }
    }

    function validate(Order memory order) external pure {
        uint256 acceptablePrice = abi.decode(order.data, (uint256));
        require(acceptablePrice > 0, "MarketOrderModule: acceptable price invalid");
    }
}
