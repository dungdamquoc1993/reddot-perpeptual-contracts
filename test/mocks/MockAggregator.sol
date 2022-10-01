// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

contract MockAggregator {
    uint256 public decimals = 8;
    uint256 price;
    uint256 lastUpdated;

    function setPrice(uint256 _price) external {
        price = _price;
        lastUpdated = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        if (lastUpdated == 0) {
            revert("No data present");
        }

        return (uint80(0), int256(price), lastUpdated, lastUpdated, uint80(0));
    }
}
