// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {IModule, OrderType, Order} from "../interfaces/IOrderBook.sol";
import {IOracle} from "../interfaces/IOracle.sol";

contract LimitOrderModule is IModule {
    function execute(IOracle oracle, Order memory order) external view {
        (uint256 limitPrice, bool triggerAboveThreshold) = abi.decode(order.data, (uint256, bool));
        uint256 markPrice = oracle.getPrice(order.indexToken);
        require(markPrice > 0, "LimitOrderModule: invalid mark price");

        bool isPriceValid = triggerAboveThreshold ? markPrice >= limitPrice : markPrice <= limitPrice;
        require(isPriceValid, "LimitOrderModule: not triggered");
    }

    function validate(Order memory order) external pure {
        (uint256 limitPrice, ) = abi.decode(order.data, (uint256, bool));
        require(limitPrice > 0, "LimitOrderModule: limit price invalid");
    }
}
