//SPDX-License-Identifier: UNLCIENSED

pragma solidity >=0.8.0;

import {IRewarder} from "../../src/interfaces/IRewarder.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockRewarder is IRewarder {
    function onReward(
        uint256 pid,
        address user,
        address recipient,
        uint256 rewardAmount,
        uint256 newLpAmount
    ) external {}

    function pendingTokens(
        uint256 pid,
        address user,
        uint256 rewardAmount
    ) external view returns (IERC20[] memory, uint256[] memory) {}
}
