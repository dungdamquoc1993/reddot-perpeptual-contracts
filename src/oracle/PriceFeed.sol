pragma solidity 0.8.15;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {UniERC20} from "../lib/UniERC20.sol";

/// @title PriceFeed
/// @notice Price feed with guard from
/// @dev Explain to a developer any extra details
contract PriceFeed is Ownable, IOracle {
    struct TokenConfig {
        /// @dev 10 ^ token decimals
        uint256 baseUnits;
        /// @dev price precision
        uint256 priceUnits;
        /// @dev chainlink pricefeed used to compare with posted price
        /// if posted price if too high or too low it will be rejected
        address chainlinkPriceFeed;
    }

    mapping(address => TokenConfig) public tokenConfig;
    /// @dev This price feed returns price in precision of 10 ^ (30 - token decimals)
    uint256 constant VALUE_PRECISION = 1e30;
    /// @notice token listed
    address[] public whitelistedTokens;
    /// @notice last reported price
    mapping(address => uint256) lastAnswers;
    /// @notice allowed price margin compared to chainlink feed
    uint256 public constant PRICE_MARGIN = 5e8; // 5%
    uint256 public constant MARGIN_PRECISION = 1e10;
    /// @dev if chainlink is not update in 5 minutes, it's not relevant anymore
    uint256 public constant CHAINLINK_PRICE_FEED_TIMEOUT = 300;

    mapping(address => bool) public isReporter;
    address[] public reporters;

    // ============ Mutative functions ============

    /// @notice report token price
    /// allow some authorized reporters only
    function postPrice(address token, uint256 price) external {
        require(isReporter[msg.sender], "PriceFeed::unauthorized");
        TokenConfig memory config = tokenConfig[token];
        require(config.baseUnits > 0, "PriceFeed::tokenNotWhitelisted");
        // simply revert if the price is out of allowed boundary and keep the current value
        // and keep the current value. May be we should take the chainlink price sometime,
        // but in most case, the chainlink price is older than the previous posted price
        _guardPrice(config, price);
        uint256 normalizedPrice = (price * VALUE_PRECISION) /
            config.baseUnits /
            config.priceUnits;

        lastAnswers[token] = normalizedPrice;
        emit PricePosted(token, normalizedPrice);
    }

    // ============ View functions ============

    function getPrice(address token) external view returns (uint256) {
        TokenConfig memory config = tokenConfig[token];
        require(config.baseUnits > 0, "PriceFeed::tokenNotConfigured");
        uint256 price = lastAnswers[token];
        require(price > 0, "PriceFeed::priceIsNotAvailable");
        return lastAnswers[token];
    }

    /// @notice get list of supported tokens for inspecting
    function getAllWhiteListedTokens()
        external
        view
        returns (address[] memory tokens)
    {
        uint256 tokenCount = whitelistedTokens.length;
        tokens = new address[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokens[i] = whitelistedTokens[i];
        }
    }

    // =========== Restrited functions ===========

    /// @notice config watched token
    /// @param token token address
    /// @param priceFeed the chainlink price feed used for reference
    /// @param priceDecimals precision of price posted by reporter, not the chainlink price feed
    function configToken(
        address token,
        address priceFeed,
        uint256 priceDecimals
    ) external onlyOwner {
        require(tokenConfig[token].baseUnits == 0, "PriceFeed::tokenAdded");
        require(priceFeed != address(0), "PriceFeed::invalidPriceFeed");
        uint256 decimals = token == UniERC20.ETH ? 18 : ERC20(token).decimals();
        tokenConfig[token] = TokenConfig({
            baseUnits: 10**decimals,
            priceUnits: 10**priceDecimals,
            chainlinkPriceFeed: priceFeed
        });
        whitelistedTokens.push(token);
        emit TokenAdded(token);
    }

    function addUpdater(address updater) external onlyOwner {
        require(!isReporter[updater], "PriceFeed::updaterAlreadyAdded");
        isReporter[updater] = true;
        reporters.push(updater);
        emit UpdaterAdded(updater);
    }

    function removeUpdater(address updater) external onlyOwner {
        require(isReporter[updater], "PriceFeed::updaterNotExists");
        isReporter[updater] = false;
        for (uint256 i = 0; i < reporters.length; i++) {
            if (reporters[i] == updater) {
                reporters[i] = reporters[reporters.length - 1];
                break;
            }
        }
        reporters.pop();
        emit UpdaterRemoved(updater);
    }

    // =========== Internal functions ===========
    function _guardPrice(TokenConfig memory config, uint256 price)
        internal
        view
    {
        uint256 guardPrice = _getGuardPrice(config);
        uint256 lowerbound = (guardPrice * (MARGIN_PRECISION - PRICE_MARGIN)) /
            MARGIN_PRECISION;
        uint256 upperbound = (guardPrice * (MARGIN_PRECISION + PRICE_MARGIN)) /
            MARGIN_PRECISION;
        require(
            lowerbound <= price && price <= upperbound,
            "PriceFeed::priceGuarded"
        );
    }

    function _getGuardPrice(TokenConfig memory config)
        internal
        view
        returns (uint256)
    {
        AggregatorV3Interface chainlinkPriceFeed = AggregatorV3Interface(
            config.chainlinkPriceFeed
        );
        (, int256 price, , uint256 updatedAt, ) = chainlinkPriceFeed
            .latestRoundData();
        uint256 priceDecimals = chainlinkPriceFeed.decimals();
        require(
            updatedAt + CHAINLINK_PRICE_FEED_TIMEOUT >= block.timestamp,
            "PriceFeed::chainlinkStaled"
        );
        return (uint256(price) * (10**priceDecimals)) / config.priceUnits;
    }

    // =========== Events ===========
    event UpdaterAdded(address);
    event UpdaterRemoved(address);
    event PricePosted(address token, uint256 price);
    event TokenAdded(address token);
}
