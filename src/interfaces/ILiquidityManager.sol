pragma solidity 0.8.15;

interface ILiquidityManager {
    function addLiquidity(uint256 amount, uint256 minLPOut) external;

    function removeLiquidity(uint256 lpAmount, uint256 minAmount) external;

    function getBalance() external returns (uint256);
}
