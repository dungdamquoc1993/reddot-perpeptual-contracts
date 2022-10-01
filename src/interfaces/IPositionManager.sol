// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

enum Side {
    LONG,
    SHORT
}

interface IPositionManager {
    function increasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeChanged,
        Side _side
    ) external;

    function decreasePosition(
        address _account,
        address _indexToken,
        uint256 _desiredCollateralReduce,
        uint256 _sizeChanged,
        Side _side
    ) external;

    function liquidatePosition(
        address account,
        address collateralToken,
        address market,
        bool isLong
    ) external;

    function validateToken(
        address indexToken,
        Side side,
        address collateralToken
    ) external view returns (bool);
}
