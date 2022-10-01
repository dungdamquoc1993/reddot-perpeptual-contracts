// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {ILPToken} from "../interfaces/ILPToken.sol";
import {PoolAsset, PoolAssetImpl} from "./PoolAsset.sol";
import {UniERC20} from "../lib/UniERC20.sol";
import {SignedInt, SignedIntOps} from "../lib/SignedInt.sol";

// Precision used for USD value
// Oracle MUST return price with decimals of (decimal_of_this_precision - token_decimals)
uint256 constant VALUE_PRECISION = 1e30;

/// @title AssetManager
/// @notice Liquitidy controling and risk management
abstract contract AssetManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using UniERC20 for IERC20;
    using SignedIntOps for SignedInt;
    using PoolAssetImpl for PoolAsset;

    uint256 constant LP_INITIAL_PRICE = 1e12; // init set to 1$

    IOracle public oracle;
    /// @notice stablecoin used as collateral for SHORT position
    address public stableToken;
    /// @notice A list of all whitelisted tokens
    mapping(address => bool) public whitelistedTokens;
    address[] public allWhitelistedTokens;
    mapping(address => PoolAsset) public poolAssets;
    /// @notice liquidtiy provider token
    ILPToken private lpToken;

    function AssetManager__initialize(address _lpToken, address _stableToken) internal {
        // require(_weth != address(0), "Configuration: invalid WETH address");
        require(_stableToken != address(0), "AssetManager: invalid stable token address");
        require(_lpToken != address(0), "AssetManager: invalid LP token address");
        whitelistedTokens[_stableToken] = true;
        allWhitelistedTokens.push(_stableToken);
        // weth = _weth;
        stableToken = _stableToken;
        lpToken = ILPToken(_lpToken);
    }

    // =========== View functions ===========
    /// @notice get total value in USD of all (whitelisted) tokens in pool
    /// with profit and lost from all opening position
    /// @dev since oracle return price in precision of 10 ^ (30 - token decimals)
    /// this function will returns dollar value with decimals of 30
    function getPoolValue() external view returns (uint256) {
        return _getPoolValue();
    }

    // =========== Administrative ===========

    function addToken(address _token) external onlyOwner {
        require(!whitelistedTokens[_token], "AssetManager: token alread added");
        whitelistedTokens[_token] = true;
        allWhitelistedTokens.push(_token);
        emit TokenWhitelisted(_token);
    }

    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "LiquidityManager::address0");
        address oldOracle = address(oracle);
        oracle = IOracle(_oracle);
        emit OracleChanged(oldOracle, _oracle);
    }

    // =========== Mutative functions ============
    function addLiquidity(
        address token,
        uint256 amount,
        uint256 minLpAmount,
        address to
    ) external payable nonReentrant {
        _requireWhitelisted(token);
        if (token != UniERC20.ETH) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        } else {
            require(msg.value == amount, "AssetManager: invalid value sent");
        }
        _addLiquidity(token, minLpAmount, to);
    }

    function removeLiquidity(
        address tokenOut,
        uint256 lpAmount,
        uint256 minOut,
        address to
    ) external nonReentrant {
        _requireWhitelisted(tokenOut);
        require(lpAmount > 0, "AssetManager: LP amount is zero");
        uint256 totalPoolValue = _getPoolValue();
        uint256 totalSupply = lpToken.totalSupply();
        uint256 tokenOutPrice = oracle.getPrice(tokenOut);
        uint256 outAmount = (lpAmount * totalPoolValue) / totalSupply / tokenOutPrice;
        require(outAmount >= minOut, "LiquidityManager::slippage");
        poolAssets[tokenOut].decreasePoolAmount(outAmount);
        // use permit token maybe
        lpToken.burnFrom(msg.sender, lpAmount);
        IERC20(tokenOut).transferTo(to, outAmount);
    }

    // ========= internal functions =========
    function _requireWhitelisted(address token) internal virtual {
        require(whitelistedTokens[token], "Configuration: token not whitelisted");
    }

    function _getAmountIn(address token) internal returns (uint256 amount) {
        _requireWhitelisted(token);
        uint256 balance = IERC20(token).getBalance(address(this));
        amount = balance - poolAssets[token].poolBalance;
        poolAssets[token].poolBalance = balance;
    }

    function _doTransferOut(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        if (_amount > 0) {
            IERC20 token = IERC20(_token);
            token.transferTo(_to, _amount);
            poolAssets[_token].poolBalance = token.getBalance(address(this));
        }
    }

    function _addLiquidity(
        address token,
        uint256 minLpAmount,
        address to
    ) internal {
        uint256 amountIn = _getAmountIn(token);
        if (amountIn == 0) {
            return;
        }
        uint256 lpAmount = _calcLpAmount(token, amountIn);
        require(lpAmount >= minLpAmount, "LPManager::>slippage");
        lpToken.mint(to, lpAmount);
        poolAssets[token].increasePoolAmount(amountIn);
    }

    function _calcLpAmount(address token, uint256 amount) internal view returns (uint256) {
        uint256 tokenPrice = oracle.getPrice(token);
        require(tokenPrice > 0, "priceNotAvailable");
        uint256 poolValue = _getPoolValue();
        uint256 lpSupply = lpToken.totalSupply();
        if (lpSupply == 0) {
            return (amount * tokenPrice) / LP_INITIAL_PRICE;
        }
        return (amount * tokenPrice * lpSupply) / poolValue;
    }

    function _getPoolValue() internal view returns (uint256 sum) {
        SignedInt memory aum = SignedIntOps.wrap(uint256(0));

        for (uint256 i = 0; i < allWhitelistedTokens.length; i++) {
            address token = allWhitelistedTokens[i];
            assert(whitelistedTokens[token]); // double check
            PoolAsset storage asset = poolAssets[token];
            uint256 price = _getPrice(token);
            if (token == stableToken) {
                aum = aum.add(asset.poolAmount * price);
            } else {
                aum = aum.add(asset.calcManagedValue(price));
            }
        }

        // aum MUST not be negative. If it is, please debug
        return aum.toUint();
    }

    function _getPrice(address token) internal view returns (uint256 price) {
        price = oracle.getPrice(token);
        require(price > 0, "PositionManager: token price not available");
    }

    // ======= Events =======
    event TokenWhitelisted(address token);
    event OracleChanged(address oldOracle, address newOracle);
}
