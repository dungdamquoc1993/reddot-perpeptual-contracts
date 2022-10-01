// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

uint256 constant FEE_PRECISION = 1e10;
uint256 constant INTEREST_RATE_PRECISION = 1e10;
uint256 constant MAX_POSITION_FEE = 1e8; // 1%

struct Fee {
    /// @notice charge when changing position size
    uint256 positionFee;
    /// @notice charge when liquidate position
    uint256 liquidationFee;
    /// @notice fee reserved rate for admin
    uint256 adminFee;
    /// @notice interest rate when borrow token to leverage
    uint256 interestRate;
    uint256 accrualInterval;
    uint256 lastAccrualTimestamp;
    /// @notice cumulated interest rate, update on epoch
    uint256 cumulativeInterestRate;
}

library FeeUtils {
    function calcInterest(
        Fee memory self,
        uint256 entryCumulativeInterestRate,
        uint256 size
    ) internal pure returns (uint256) {
        return (size * (self.cumulativeInterestRate - entryCumulativeInterestRate)) / INTEREST_RATE_PRECISION;
    }

    function calcPositionFee(Fee memory self, uint256 sizeChanged) internal pure returns (uint256) {
        return (sizeChanged * self.positionFee) / FEE_PRECISION;
    }

    // TODO: fixed value or based on size?
    function calcLiquidationFee(Fee memory self, uint256 size) internal pure returns (uint256) {
        return (size * self.liquidationFee) / FEE_PRECISION;
    }

    function calcAdminFee(Fee memory self, uint256 feeAmount) internal pure returns (uint256) {
        return (feeAmount * self.adminFee) / FEE_PRECISION;
    }

    function cumulativeInterest(Fee storage self) internal {
        uint256 _now = block.timestamp;
        if (self.lastAccrualTimestamp == 0) {
            // accrue interest for the first time
            self.lastAccrualTimestamp = _now;
            return;
        }

        if (self.lastAccrualTimestamp + self.accrualInterval > _now) {
            return;
        }

        uint256 nInterval = (_now - self.lastAccrualTimestamp) / self.accrualInterval;
        self.cumulativeInterestRate += nInterval * self.interestRate;
        self.lastAccrualTimestamp += nInterval * self.accrualInterval;
    }

    function setInterestRate(
        Fee storage self,
        uint256 interestRate,
        uint256 accrualInterval
    ) internal {
        self.accrualInterval = accrualInterval;
        self.interestRate = interestRate;
    }

    function setFee(
        Fee storage self,
        uint256 positionFee,
        uint256 liquidationFee,
        uint256 adminFee
    ) internal {
        require(positionFee <= MAX_POSITION_FEE, "Fee: max position fee exceeded");
        self.positionFee = positionFee;
        self.liquidationFee = liquidationFee;
        self.adminFee = adminFee;
    }
}
