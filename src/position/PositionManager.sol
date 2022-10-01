// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {SafeERC20, IERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Side} from "../interfaces/IPositionManager.sol";
import {Fee, FeeUtils} from "./Fee.sol";
import {Position, PositionUtils, IncreasePositionResult, DecreasePositionResult} from "./Position.sol";
import {SignedInt, SignedIntOps} from "../lib/SignedInt.sol";
import {UniERC20} from "../lib/UniERC20.sol";
import {PoolAsset, PoolAssetImpl} from "../assets/PoolAsset.sol";
import {AssetManager} from "../assets/AssetManager.sol";

abstract contract PositionManager is AssetManager {
    using PositionUtils for Position;
    using SignedIntOps for SignedInt;
    using FeeUtils for Fee;
    using SafeERC20 for IERC20;
    using UniERC20 for IERC20;
    using PoolAssetImpl for PoolAsset;

    Fee public fee;

    /// @notice positions tracks all open positions
    mapping(bytes32 => Position) public positions;
    mapping(address => uint256) public maxLeverages;
    address public orderBook;

    modifier onlyOrderBook() {
        require(msg.sender == orderBook, "PositionManager: only orderbook allowed");
        _;
    }

    function PositionManager__initialize(
        uint256 _positionFee,
        uint256 _liquidationFee,
        uint256 _adminFee,
        uint256 _interestRate,
        uint256 _accrualInterval
    ) internal {
        fee.positionFee = _positionFee;
        fee.liquidationFee = _liquidationFee;
        fee.adminFee = _adminFee;
        fee.interestRate = _interestRate;
        fee.accrualInterval = _accrualInterval;
    }

    /* ========= VIEW FUNCTIONS ========= */

    function validateToken(address _indexToken, Side _side, address _collateralToken) external view returns(bool) {
        return _collateralToken == getCollateralToken(_side, _indexToken);
    }

    struct PositionView {
        uint256 size;
        uint256 collateralValue;
        uint256 entryPrice;
        uint256 pnl;
        uint256 reserveAmount;
        bool hasProfit;
    }

    function getPosition(
        address _owner,
        address _indexToken,
        Side _side
    ) external view returns (PositionView memory result) {
        address collateralToken = getCollateralToken(_side, _indexToken);
        bytes32 positionKey = getPositionKey(_owner, _indexToken, collateralToken, _side);
        Position memory position = positions[positionKey];
        uint256 indexPrice = _getPrice(_indexToken);
        SignedInt memory pnl = PositionUtils.calcPnl(_side, position.size, position.entryPrice, indexPrice);

        result.size = position.size;
        result.collateralValue = position.collateralValue;
        result.pnl = pnl.abs;
        result.hasProfit = pnl.gt(uint256(0));
        result.entryPrice = position.entryPrice;
        result.reserveAmount = position.reserveAmount;
    }

    /* ========= MUTATIVE FUNCTIONS ======= */
    /// @notice increase position long or short
    /// @dev in case of long position, we keep index token as collateral
    /// in case of short position, we keep stable coin as collateral
    function increasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeChanged,
        Side _side
    ) external onlyOrderBook {
        fee.cumulativeInterest();
        address _collateralToken = getCollateralToken(_side, _indexToken);
        uint256 indexPrice = _getPrice(_indexToken);
        uint256 collateralPrice = _getPrice(_collateralToken);
        uint256 collateralAmount = _getAmountIn(_collateralToken);

        bytes32 positionKey = getPositionKey(_account, _indexToken, _collateralToken, _side);
        Position storage position = positions[positionKey];

        // increase position
        IncreasePositionResult memory result = position.increase(
            fee,
            _side,
            _sizeChanged,
            collateralAmount,
            indexPrice,
            collateralPrice
        );
        poolAssets[_collateralToken].increaseReserve(result.reserveAdded, result.adminFee);

        // update asset based on position changed
        if (_side == Side.LONG) {
            poolAssets[_collateralToken].increaseLongPosition(
                _sizeChanged,
                collateralAmount,
                result.collateralValueAdded,
                result.adminFee,
                result.feeValue
            );
        } else {
            poolAssets[_indexToken].increaseShortPosition(_sizeChanged, indexPrice);
        }

        emit IncreasePosition(
            positionKey,
            _account,
            _collateralToken,
            _indexToken,
            collateralAmount,
            _sizeChanged,
            _side,
            indexPrice
        );

        emit UpdatePosition(
            positionKey,
            position.size,
            position.collateralValue,
            position.entryPrice,
            position.entryInterestRate,
            position.reserveAmount,
            indexPrice
        );
    }

    /// @notice decrease position long or short
    function decreasePosition(
        address _account,
        address _indexToken,
        uint256 _desiredCollateralReduce,
        uint256 _sizeChanged,
        Side _side
    ) external onlyOrderBook {
        fee.cumulativeInterest();
        address _collateralToken = getCollateralToken(_side, _indexToken);
        uint256 indexPrice = _getPrice(_indexToken);
        uint256 collateralPrice = _getPrice(_collateralToken);

        bytes32 positionKey = getPositionKey(_account, _indexToken, _collateralToken, _side);
        Position storage position = positions[positionKey];

        // decrease position
        DecreasePositionResult memory result = position.decrease(
            fee,
            _side,
            _sizeChanged,
            _desiredCollateralReduce,
            indexPrice,
            collateralPrice
        );

        // reduce reserve amounts
        poolAssets[_collateralToken].decreaseReserve(result.reserveReduced, result.adminFee);

        if (_side == Side.LONG) {
            poolAssets[_collateralToken].decreaseLongPosition(
                result.collateralValueReduced,
                _sizeChanged,
                result.payout,
                result.adminFee
            );
        } else {
            poolAssets[_indexToken].decreaseShortPosition(result.pnl, _sizeChanged);
        }

        if (position.size == 0) {
            // delete position when closed
            delete positions[positionKey];

            emit DecreasePosition(
                positionKey,
                _account,
                _collateralToken,
                _indexToken,
                result.collateralValueReduced,
                _sizeChanged,
                _side,
                indexPrice
            );
            emit ClosePosition(
                positionKey,
                position.size,
                position.collateralValue,
                position.entryPrice,
                position.entryInterestRate,
                position.reserveAmount
            );
        } else {
            emit DecreasePosition(
                positionKey,
                _account,
                _collateralToken,
                _indexToken,
                result.collateralValueReduced,
                _sizeChanged,
                _side,
                indexPrice
            );
            emit UpdatePosition(
                positionKey,
                position.size,
                position.collateralValue,
                position.entryPrice,
                position.entryInterestRate,
                position.reserveAmount,
                indexPrice
            );
        }
        _doTransferOut(_collateralToken, _account, result.payout);
    }

    /// @notice liquidate position
    function liquidatePosition(
        address _account,
        address _indexToken,
        Side _side
    ) external onlyOrderBook {
        fee.cumulativeInterest();
        address _collateralToken = getCollateralToken(_side, _indexToken);
        uint256 indexPrice = _getPrice(_indexToken);
        uint256 collateralPrice = _getPrice(_collateralToken);

        bytes32 positionKey = getPositionKey(_account, _indexToken, _collateralToken, _side);
        Position storage position = positions[positionKey];

        DecreasePositionResult memory result = position.liquidate(fee, _side, indexPrice, collateralPrice);
        uint256 feeAmount = fee.calcAdminFee(result.feeValue) / collateralPrice;
        poolAssets[_collateralToken].decreaseReserve(position.reserveAmount, feeAmount);

        if (_side == Side.LONG) {
            // decrease full position size without paying out anything
            poolAssets[_collateralToken].decreaseLongPosition(position.size, position.collateralValue, 0, feeAmount);
        } else {
            poolAssets[_indexToken].decreaseShortPosition(result.pnl, position.size);
        }

        delete positions[positionKey];

        emit LiquidatePosition(
            positionKey,
            _account,
            _collateralToken,
            _indexToken,
            _side,
            position.size,
            position.collateralValue,
            position.reserveAmount,
            indexPrice
        );
    }

    /* ========= PRIVATE FUNCTIONS ======== */

    /// @notice get collateral token based on side of index token
    /// collateral token is token protocol kept as reserve, in order to pay user at any given time
    /// In case of long, we should keep index token as collateral.
    function getCollateralToken(Side _side, address _indexToken) internal view returns (address) {
        require(whitelistedTokens[_indexToken], "PositionManager: onlyWhitelistedTokens");
        if (_side == Side.LONG) {
            require(_indexToken != stableToken, "PositionManager: cannot long stable token");
            return _indexToken;
        } else {
            return stableToken;
        }
    }

    /// @notice get key of position
    function getPositionKey(
        address _account,
        address _indexToken,
        address _collateralToken,
        Side side
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _indexToken, _collateralToken, side));
    }

    /* ========== EVENTS ========== */
    event SetOrderBook(address orderBook);

    event IncreasePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        uint256 collateralValue,
        uint256 sizeChanged,
        Side side,
        uint256 indexPrice
    );
    event UpdatePosition(
        bytes32 key,
        uint256 size,
        uint256 collateralValue,
        uint256 entryPrice,
        uint256 entryInterestRate,
        uint256 reserveAmount,
        uint256 indexPrice
    );
    event DecreasePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        uint256 collateralChanged,
        uint256 sizeChanged,
        Side side,
        uint256 indexPrice
    );
    event ClosePosition(
        bytes32 key,
        uint256 size,
        uint256 collateralValue,
        uint256 entryPrice,
        uint256 entryInterestRate,
        uint256 reserveAmount
    );
    event LiquidatePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        Side side,
        uint256 size,
        uint256 collateralValue,
        uint256 reserveAmount,
        uint256 indexPrice
    );
}
