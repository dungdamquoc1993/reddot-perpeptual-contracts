// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {IOracle} from "../interfaces/IOracle.sol";
import {Side} from "../interfaces/IPositionManager.sol";

enum OrderType {
    INCREASE,
    DECREASE
}

/// @notice Order info
/// @dev The executor MUST save this info and call execute method whenever they think it fulfilled.
/// The approriate module will check for their condition and then execute, returning success or not
struct Order {
    IModule module;
    address owner;
    address indexToken;
    address collateralToken;
    uint256 sizeChanged;
    /// @notice when increase, collateralAmount is desired amount of collateral used as margin.
    /// When decrease, collateralAmount is value in USD of collateral user want to reduce from
    /// their position
    uint256 collateralAmount;
    uint256 executionFee;
    /// @notice To prevent front-running, order MUST be executed on next block
    uint256 submissionBlock;
    uint256 submissionTimestamp;
    // long or short
    Side side;
    OrderType orderType;
    // extra data for each order type
    bytes data;
}

/// @notice Order module, will parse orders and call to corresponding handler.
/// After execution complete, module will pass result to position manager to
/// update related position
/// Will be some kind of: StopLimitHandler, LimitHandler, MarketHandler...
interface IModule {
    function execute(IOracle oracle, Order memory order) external;

    function validate(Order memory order) external view;
}

interface IOrderBook {
    function placeOrder(
        IModule _module,
        address _indexToken,
        address _collateralToken,
        uint256 _side,
        OrderType _orderType,
        uint256 _sizeChanged,
        bytes calldata _data
    ) external payable;

    function executeOrder(bytes32 _key, address payable _feeTo) external;

    function executeOrders(bytes32[] calldata _key, address payable _feeTo) external;

    function cancelOrder(bytes32 _key) external;
}
