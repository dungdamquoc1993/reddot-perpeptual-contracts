// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {IOrderBook} from "../interfaces/IOrderBook.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";

interface IPriceFeed {
    function postPrice(address token, uint price) external;
}

/**
 * @title PriceReporter
 * @notice Utility contract to call post prices and execute orders on a single transaction
 */
contract PriceReporter is Ownable {
    IPriceFeed private immutable oracle;
    IOrderBook private immutable orderBook;
    mapping(address => bool) public isReporter;
    address[] public reporters;

    constructor(address _oracle, address _orderBook) {
        require(_oracle != address(0), "invalid oracle");
        require(_orderBook != address(0), "invalid position manager");
        oracle = IPriceFeed(_oracle);
        orderBook = IOrderBook(_orderBook);
    }

    function postPriceAndExecuteOrders(address[] calldata tokens, uint[] calldata prices, bytes32[] calldata orders) external {
        require(isReporter[msg.sender], "unauthorized");
        require(tokens.length == prices.length, "invalid token prices data");
        for (uint256 i = 0; i < tokens.length; i++) {
            oracle.postPrice(tokens[i], prices[i]);
        }

        orderBook.executeOrders(orders, payable(msg.sender));
    }

    function addUpdater(address updater) external onlyOwner {
        require(!isReporter[updater], "PriceFeed::updaterAlreadyAdded");
        isReporter[updater] = true;
        reporters.push(updater);
    }

    function removeUpdater(address updater) external onlyOwner {
        require(isReporter[updater], "PriceFeed::updaterNotExists");
        isReporter[updater] = false;
        for (uint256 i = 0; i < reporters.length; i++) {
            if (reporters[i] == updater) {
                reporters[i] = reporters[reporters.length - 1];
                break;
            }
        }
        reporters.pop();
    }
}
