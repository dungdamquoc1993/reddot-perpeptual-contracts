// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {SignedInt, SignedIntOps} from "../lib/SignedInt.sol";
import {Fee, FeeUtils} from "./Fee.sol";
import {Side} from "../interfaces/IPositionManager.sol";

uint256 constant MAX_LEVERAGE = 30;

struct Position {
    /// @dev contract size is evaluated in dollar
    uint256 size;
    /// @dev collateral value in dollar
    uint256 collateralValue;
    /// @dev contract size in indexToken
    uint256 reserveAmount;
    /// @dev average entry price
    uint256 entryPrice;
    /// @dev last cumulative interest rate
    uint256 entryInterestRate;
}

struct IncreasePositionResult {
    uint256 reserveAdded;
    uint256 collateralValueAdded;
    uint256 feeValue;
    uint256 adminFee;
}

struct DecreasePositionResult {
    uint256 collateralValueReduced;
    uint256 reserveReduced;
    uint256 feeValue;
    uint256 adminFee;
    uint256 payout;
    SignedInt pnl;
}

library PositionUtils {
    using SignedIntOps for SignedInt;
    using FeeUtils for Fee;

    /// @notice increase position size and/or collateral
    /// @param position position to update
    /// @param fee fee config
    /// @param side long or shor
    /// @param sizeChanged value in USD
    /// @param collateralAmount value in USD
    /// @param indexPrice price of index token
    /// @param collateralPrice price of collateral token
    function increase(
        Position storage position,
        Fee memory fee,
        Side side,
        uint256 sizeChanged,
        uint256 collateralAmount,
        uint256 indexPrice,
        uint256 collateralPrice
    ) internal returns (IncreasePositionResult memory result) {
        result.collateralValueAdded = collateralPrice * collateralAmount;
        result.feeValue =
            fee.calcInterest(position.entryInterestRate, position.size) +
            fee.calcPositionFee(sizeChanged);
        result.adminFee = fee.calcAdminFee(result.feeValue) / collateralPrice;
        require(
            position.collateralValue + result.collateralValueAdded > result.feeValue,
            "Position: increase cause liquidation"
        );

        result.reserveAdded = sizeChanged / indexPrice;

        position.entryPrice = calcAveragePrice(side, position.size, sizeChanged, position.entryPrice, indexPrice);
        position.collateralValue = position.collateralValue + result.collateralValueAdded - result.feeValue;
        position.size = position.size + sizeChanged;
        position.entryInterestRate = fee.cumulativeInterestRate;
        position.reserveAmount += result.reserveAdded;

        validatePosition(position, false, MAX_LEVERAGE);
        validateLiquidation(position, fee, side, indexPrice);
    }

    /// @notice decrease position size and/or collateral
    /// @param collateralChanged collateral value in $ to reduce
    function decrease(
        Position storage position,
        Fee memory fee,
        Side side,
        uint256 sizeChanged,
        uint256 collateralChanged,
        uint256 indexPrice,
        uint256 collateralPrice
    ) internal returns (DecreasePositionResult memory result) {
        result = decreaseUnchecked(position, fee, side, sizeChanged, collateralChanged, indexPrice, collateralPrice);
        validatePosition(position, false, MAX_LEVERAGE);
        validateLiquidation(position, fee, side, indexPrice);
    }

    function liquidate(
        Position storage position,
        Fee memory fee,
        Side side,
        uint256 indexPrice,
        uint256 collateralPrice
    ) internal returns (DecreasePositionResult memory result) {
        (bool allowed, , , ) = liquidatePositionAllowed(position, fee, side, indexPrice);
        require(allowed, "Position: can not liquidate");
        result = decreaseUnchecked(position, fee, side, position.size, 0, indexPrice, collateralPrice);
        assert(position.size == 0); // double check
        assert(position.collateralValue == 0);
    }

    function decreaseUnchecked(
        Position storage position,
        Fee memory fee,
        Side side,
        uint256 sizeChanged,
        uint256 collateralChanged,
        uint256 indexPrice,
        uint256 collateralPrice
    ) internal returns (DecreasePositionResult memory result) {
        require(position.size >= sizeChanged, "Position: decrease too much");
        require(position.collateralValue >= collateralChanged, "Position: reduce collateral too much");

        result.reserveReduced = (position.reserveAmount * sizeChanged) / position.size;
        collateralChanged = collateralChanged > 0
            ? collateralChanged
            : (position.collateralValue * sizeChanged) / position.size;

        result.pnl = calcPnl(side, sizeChanged, position.entryPrice, indexPrice);
        result.feeValue =
            fee.calcInterest(position.entryInterestRate, position.size) +
            fee.calcPositionFee(sizeChanged);
        result.adminFee = fee.calcAdminFee(result.feeValue) / collateralPrice;

        SignedInt memory payoutValue = result.pnl.add(collateralChanged).sub(result.feeValue);
        SignedInt memory collateral = SignedIntOps.wrap(position.collateralValue).sub(collateralChanged);
        if (payoutValue.isNeg()) {
            // deduct uncovered lost from collateral
            collateral = collateral.add(payoutValue);
        }

        uint256 collateralValue = collateral.isNeg() ? 0 : collateral.abs;
        result.collateralValueReduced = position.collateralValue - collateralValue;
        position.collateralValue = collateralValue;
        position.size = position.size - sizeChanged;
        position.entryInterestRate = fee.cumulativeInterestRate;
        position.reserveAmount = position.reserveAmount - result.reserveReduced;
        result.payout = payoutValue.isNeg() ? 0 : payoutValue.abs / collateralPrice;
    }

    /// @notice calculate new avg entry price when increase position
    /// @dev for longs: nextAveragePrice = (nextPrice * nextSize)/ (nextSize + delta)
    ///      for shorts: nextAveragePrice = (nextPrice * nextSize) / (nextSize - delta)
    function calcAveragePrice(
        Side side,
        uint256 lastSize,
        uint256 increasedSize,
        uint256 entryPrice,
        uint256 nextPrice
    ) internal pure returns (uint256) {
        if (lastSize == 0) {
            return nextPrice;
        }
        SignedInt memory pnl = calcPnl(side, lastSize, entryPrice, nextPrice);
        SignedInt memory nextSize = SignedIntOps.wrap(lastSize + increasedSize);
        SignedInt memory divisor = side == Side.LONG ? nextSize.add(pnl) : nextSize.sub(pnl);
        return nextSize.mul(nextPrice).div(divisor).toUint();
    }

    function calcPnl(
        Side side,
        uint256 positionSize,
        uint256 entryPrice,
        uint256 indexPrice
    ) internal pure returns (SignedInt memory) {
        if (positionSize == 0) {
            return SignedIntOps.wrap(uint256(0));
        }
        if (side == Side.LONG) {
            return SignedIntOps.wrap(indexPrice).sub(entryPrice).mul(positionSize).div(entryPrice);
        } else {
            return SignedIntOps.wrap(entryPrice).sub(indexPrice).mul(positionSize).div(entryPrice);
        }
    }

    function validateLiquidation(
        Position storage position,
        Fee memory fee,
        Side side,
        uint256 indexPrice
    ) internal view {
        (bool liquidated, , , ) = liquidatePositionAllowed(position, fee, side, indexPrice);
        require(!liquidated, "Position: liquidated");
    }

    function validatePosition(
        Position storage position,
        bool isIncrease,
        uint256 maxLeverage
    ) internal view {
        if (isIncrease) {
            require(position.size >= 0, "Position: invalid size");
        }
        require(position.size >= position.collateralValue, "Position: invalid leverage");
        require(position.size <= position.collateralValue * maxLeverage, "POSITION: max leverage exceeded");
    }

    function liquidatePositionAllowed(
        Position storage position,
        Fee memory fee,
        Side side,
        uint256 indexPrice
    )
        internal
        view
        returns (
            bool allowed,
            uint256 feeValue,
            uint256 remainingCollateralValue,
            SignedInt memory pnl
        )
    {
        // calculate fee needed when close position
        feeValue =
            fee.calcInterest(position.entryInterestRate, position.size) +
            fee.calcPositionFee(position.size) +
            fee.calcLiquidationFee(position.size);

        pnl = calcPnl(side, position.size, position.entryPrice, indexPrice);

        SignedInt memory remainingCollateral = pnl.add(position.collateralValue).sub(feeValue);

        (allowed, remainingCollateralValue) = remainingCollateral.isNeg()
            ? (true, 0)
            : (false, remainingCollateral.abs);
    }
}
