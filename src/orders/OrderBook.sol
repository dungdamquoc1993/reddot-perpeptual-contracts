// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {ReentrancyGuard} from "openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Initializable} from "openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPositionManager, Side} from "../interfaces/IPositionManager.sol";
import {UniERC20} from "../lib/UniERC20.sol";
import {RevertReasonParser} from "../lib/RevertReasonParser.sol";
import {IModule, Order, OrderType} from "../interfaces/IOrderBook.sol";
import {IOracle} from "../interfaces/IOracle.sol";

contract OrderBook is Ownable, ReentrancyGuard, Initializable {
    using SafeERC20 for IERC20;
    using UniERC20 for IERC20;

    /// @notice all placed order
    mapping(bytes32 => Order) public orders;
    IPositionManager public positionManager;
    uint256 public minExecutionFee = 3e14; // 0.0003ETH

    mapping(address => bool) public isSupportedModule;
    address[] public supportedModules;
    IOracle public oracle;

    receive() external payable {
        // prevent send ETH directly to contract
        require(msg.sender != tx.origin, "OrderBook: only WETH allowed");
    }

    function initialize(
        address _positionManager,
        address _oracle,
        uint256 _minExecutionFee
    ) external initializer {
        require(_positionManager != address(0), "OrderBook: invalid position manager");
        require(_oracle != address(0), "invalid oracle");
        minExecutionFee = _minExecutionFee;
        positionManager = IPositionManager(_positionManager);
        oracle = IOracle(_oracle);
    }

    /// @notice place order by deposit an amount of ETH
    /// in case of non-ETH order, amount of msg.value will be used as execution fee
    function placeOrder(
        IModule _module,
        address _indexToken,
        address _collateralToken,
        Side _side,
        OrderType _orderType,
        uint256 _sizeChanged,
        bytes calldata _data
    ) external payable nonReentrant returns (bytes32) {
        require(isSupportedModule[address(_module)], "OrderBook: module not supported");
        require(positionManager.validateToken(_indexToken, _side, _collateralToken), "OrderBook: invalid tokens");

        uint256 ethAmount = msg.value;
        uint256 executionFee;
        uint256 collateralAmount;
        bytes memory auxData;

        if (_orderType == OrderType.INCREASE) {
            address purchaseToken;
            uint256 purchaseAmount;
            (purchaseToken, purchaseAmount, collateralAmount, auxData) = abi.decode(
                _data,
                (address, uint256, uint256, bytes)
            );

            // check: need swap?
            (purchaseToken, purchaseAmount) = purchaseToken == address(0)
                ? (_collateralToken, collateralAmount)
                : (purchaseToken, purchaseAmount);

            if (purchaseToken == UniERC20.ETH) {
                executionFee = ethAmount - collateralAmount;
            } else {
                executionFee = ethAmount;
                collateralAmount = _transferIn(purchaseToken, purchaseAmount);
            }
        } else {
            executionFee = ethAmount;
            (collateralAmount, auxData) = abi.decode(_data, (uint256, bytes));
        }

        require(executionFee >= minExecutionFee, "OrderBook: insufficient execution fee");

        Order memory order = Order({
            module: _module,
            owner: msg.sender,
            indexToken: _indexToken,
            sizeChanged: _sizeChanged,
            collateralToken: _collateralToken,
            collateralAmount: collateralAmount,
            submissionBlock: block.number,
            submissionTimestamp: block.timestamp,
            executionFee: executionFee,
            side: _side,
            orderType: _orderType,
            data: auxData
        });

        _module.validate(order);
        bytes32 key = _keyOf(order);
        orders[key] = order;
        emit OrderPlaced(key);
        return key;
    }

    function _transferIn(address _token, uint256 _amount) internal returns (uint256) {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        return token.balanceOf(address(this)) - balance;
    }

    function executeOrders(bytes32[] calldata _keys, address payable _feeTo) external nonReentrant {
        for (uint256 i = 0; i < _keys.length; i++) {
            bytes32 key = _keys[i];
            _tryExecuteOrder(key, _feeTo);
        }
    }

    function executeOrder(bytes32 _key, address payable _feeTo) external nonReentrant {
        (bool success, bytes memory reason) = _tryExecuteOrder(_key, _feeTo);
        if (!success) {
            revert(RevertReasonParser.parse(reason, "OrderBook: excute order failed: "));
        }
    }

    function _tryExecuteOrder(bytes32 _key, address payable _feeTo)
        internal
        returns (bool success, bytes memory reason)
    {
        Order memory order = orders[_key];
        if (!isSupportedModule[address(order.module)]) {
            return (false, abi.encodeWithSignature("Error(string)", "Unsupported module"));
        }

        if (block.number <= order.submissionBlock) {
            return (false, abi.encodeWithSignature("Error(string)", "Block not pass"));
        }

        try order.module.execute(oracle, order) {
            delete orders[_key];

            if (order.orderType == OrderType.INCREASE) {
                IERC20(order.collateralToken).transferTo(address(positionManager), order.collateralAmount);
                positionManager.increasePosition(order.owner, order.indexToken, order.sizeChanged, order.side);
            } else {
                positionManager.decreasePosition(
                    order.owner,
                    order.indexToken,
                    order.collateralAmount,
                    order.sizeChanged,
                    order.side
                );
            }

            UniERC20.safeTransferETH(_feeTo, order.executionFee);
            emit OrderExecuted(_key);
            return (true, bytes(""));
        } catch (bytes memory errorMessage) {
            return (false, errorMessage);
        }
    }

    function cancelOrder(bytes32 _key) external nonReentrant {
        Order memory order = orders[_key];
        require(order.owner == msg.sender, "OrderBook: unauthorized cancellation");
        delete orders[_key];

        UniERC20.safeTransferETH(order.owner, order.executionFee);
        if (order.orderType == OrderType.INCREASE) {
            IERC20(order.collateralToken).transferTo(order.owner, order.collateralAmount);
        }
        emit OrderCancelled(_key);
    }

    function _keyOf(Order memory order) internal pure returns (bytes32) {
        return keccak256(abi.encode(order));
    }

    // ============ Administrative =============
    function supportModule(address _module) external onlyOwner {
        require(_module != address(0), "OrderBook: invalid module");
        require(!isSupportedModule[_module], "OrderBook: module already added");
        isSupportedModule[_module] = true;
        supportedModules.push(_module);
        emit ModuleSupported(_module);
    }

    function unsupportModule(address _module) external onlyOwner {
        require(isSupportedModule[_module], "OrderBook: module not supported");
        isSupportedModule[_module] = false;

        for (uint256 i = 0; i < supportedModules.length; i++) {
            if (supportedModules[i] == _module) {
                supportedModules[i] = supportedModules[supportedModules.length - 1];
                break;
            }
        }
        supportedModules.pop();
        emit ModuleUnsupported(_module);
    }

    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "OrderBook: invalid oracle addres");
        oracle = IOracle(_oracle);
        emit OracleChanged(_oracle);
    }

    function setPositionManager(address _positionManager) external onlyOwner {
        require(_positionManager != address(0), "OrderBook: invalid position manager addres");
        positionManager = IPositionManager(_positionManager);
        emit PositionManagerChanged(_positionManager);
    }

    event OrderPlaced(bytes32 indexed key);
    event OrderCancelled(bytes32 indexed key);
    event OrderExecuted(bytes32 indexed key);
    event ModuleSupported(address module);
    event ModuleUnsupported(address module);
    event OracleChanged(address);
    event PositionManagerChanged(address);
}
