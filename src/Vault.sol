// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {Initializable} from "openzeppelin/contracts/proxy/utils/Initializable.sol";
import {PositionManager} from "./position/PositionManager.sol";
import {Fee, FeeUtils} from "./position/Fee.sol";

contract Vault is Initializable, PositionManager {
    using FeeUtils for Fee;

    address public feeDistributor;

    function initialize(
        address _lpToken,
        address _stableToken,
        uint256 _positionFee,
        uint256 _liquidationFee,
        uint256 _adminFee,
        uint256 _interestRate,
        uint256 _accrualInterval
    ) external initializer {
        AssetManager__initialize(_lpToken, _stableToken);
        PositionManager__initialize(_positionFee, _liquidationFee, _adminFee, _interestRate, _accrualInterval);
    }

    function setFee(
        uint256 _positionFee,
        uint256 _liquidationFee,
        uint256 _adminFee,
        uint256 _interestRatePerYear,
        uint256 _accrualInterval
    ) external onlyOwner {
        fee.setInterestRate(_interestRatePerYear, _accrualInterval);
        fee.setFee(_positionFee, _liquidationFee, _adminFee);
    }

    function setOrderBook(address _orderBook) external onlyOwner {
        require(_orderBook != address(0), "Vault: invalid order book address");
        orderBook = _orderBook;
        emit SetOrderBook(_orderBook);
    }

    function withdrawFee(address _token, address _recipient) external {
        require(msg.sender == feeDistributor, "Vault: only fee distributor allowed");
        _requireWhitelisted(_token);
        uint256 amount = poolAssets[_token].feeReserve;
        poolAssets[_token].feeReserve = 0;
        _doTransferOut(_token, _recipient, amount);
        emit WithdrawFee(_token, _recipient, amount);
    }

    function setFeeDistributor(address _feeDistributor) external onlyOwner {
        require(_feeDistributor != address(0), "Vault: invalid fee distributor");
        feeDistributor = _feeDistributor;
        emit SetFeeDistributor(feeDistributor);
    }

    // =========== Events ===========
    event WithdrawFee(address token, address recipient, uint256 amount);
    event SetFeeDistributor(address feeDistributor);
}
