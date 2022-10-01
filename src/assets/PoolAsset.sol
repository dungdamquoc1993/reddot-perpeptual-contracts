// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {Side} from "../interfaces/IPositionManager.sol";
import {PositionUtils} from "../position/Position.sol";
import {SignedInt, SignedIntOps} from "../lib/SignedInt.sol";

struct PoolAsset {
    /// @notice amount of token deposited (via add liquidity or increase long position)
    uint256 poolAmount;
    /// @notice amount of token reserved for paying out when user decrease long position
    uint256 reservedAmount;
    /// @notice amount reserved for fee
    uint256 feeReserve;
    /// @notice total borrowed (in USD) to leverage
    uint256 guaranteedValue;
    /// @notice total size of all short positions
    uint256 totalShortSize;
    /// @notice average entry price of all short position
    uint256 averageShortPrice;
    /// @notice recorded balance of token in pool
    uint256 poolBalance;
}

library PoolAssetImpl {
    using SignedIntOps for SignedInt;

    /// @notice increase reserve when increase position
    /// fee also taken to fee reserve
    function increaseReserve(
        PoolAsset storage self,
        uint256 reserveAdded,
        uint256 feeAmount
    ) internal {
        self.reservedAmount += reserveAdded;
        require(self.reservedAmount <= self.poolAmount, "PoolAsset: reserve exceed pool amount");
        self.feeReserve += feeAmount;
    }

    function decreaseReserve(
        PoolAsset storage self,
        uint256 reserveReduced,
        uint256 feeAmount
    ) internal {
        require(self.reservedAmount >= reserveReduced, "Position: reserve reduce too much");
        self.reservedAmount -= reserveReduced;
        self.feeReserve += feeAmount;
    }

    /// @notice recalculate global LONG position for collateral asset
    function increaseLongPosition(
        PoolAsset storage self,
        uint256 sizeChanged,
        uint256 collateralAmountIn,
        uint256 collateralValueIn,
        uint256 adminFee,
        uint256 feeValue
    ) internal {
        // remember pool amounts is amount of collateral token
        // the fee is deducted from collateral in, so we reduce it from poolAmount and guaranteed value
        self.poolAmount = self.poolAmount + collateralAmountIn - adminFee;
        // ajust guaranteed
        self.guaranteedValue = self.guaranteedValue + sizeChanged + feeValue - collateralValueIn;
    }

    /// @notice recalculate global short position for index asset
    function increaseShortPosition(
        PoolAsset storage self,
        uint256 sizeChanged,
        uint256 indexPrice
    ) internal {
        // recalculate total short position
        uint256 lastSize = self.totalShortSize;
        uint256 entryPrice = self.averageShortPrice;
        self.averageShortPrice = PositionUtils.calcAveragePrice(Side.SHORT, lastSize, sizeChanged, entryPrice, indexPrice);
        self.totalShortSize = lastSize + sizeChanged;
    }

    function decreaseLongPosition(
        PoolAsset storage self,
        uint256 collateralChanged,
        uint256 sizeChanged,
        uint256 payoutAmount,
        uint256 adminFee
    ) internal {
        // update guaranteed
        // guaranteed = size - collateral
        // NOTE: collateralChanged is fee excluded
        self.guaranteedValue = self.guaranteedValue + collateralChanged - sizeChanged;
        self.poolAmount -= payoutAmount + adminFee;
    }

    function decreaseShortPosition(
        PoolAsset storage self,
        SignedInt memory pnl,
        uint256 sizeChanged
    ) internal {
        SignedInt memory poolAmount = pnl.add(self.poolAmount);
        self.poolAmount = poolAmount.isNeg() ? 0 : poolAmount.abs;
        // update short position
        self.totalShortSize -= sizeChanged;
    }

    function calcManagedValue(PoolAsset storage self, uint256 price) internal view returns (SignedInt memory aum) {
        SignedInt memory shortPnl = self.totalShortSize == 0
            ? SignedIntOps.wrap(uint256(0))
            : SignedIntOps.wrap(self.averageShortPrice).sub(price).mul(self.totalShortSize).div(self.averageShortPrice);

        aum = SignedIntOps.wrap(self.poolAmount).sub(self.reservedAmount).mul(price).add(self.guaranteedValue);
        aum = aum.sub(shortPnl);
    }

    function increasePoolAmount(PoolAsset storage self, uint256 amount) internal {
        self.poolAmount += amount;
    }

    function decreasePoolAmount(PoolAsset storage self, uint256 amount) internal {
        self.poolAmount -= amount;
        require(self.poolAmount >= self.reservedAmount, "PoolAsset: reduce pool amount too much");
    }
}
