pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {Position, PositionUtils, IncreasePositionResult, DecreasePositionResult} from "../../src/position/Position.sol";
import {Side} from "../../src/interfaces/IPositionManager.sol";
import {Fee} from "../../src/position/Fee.sol";
import {SignedInt, POS, NEG} from "../../src/lib/SignedInt.sol";

contract PositionTest is Test {
    using PositionUtils for Position;
    Position position;
    Fee fee;

    function setUp() external {
        fee = Fee({
            positionFee: 1e7, // 0.1%
            adminFee: 1e9,
            interestRate: 1e6, // about 0.8% per year
            cumulativeInterestRate: 0,
            accrualInterval: 3600,
            lastAccrualTimestamp: 0,
            liquidationFee: 0
        });
    }

    function testLongPosition() external {
        // token decimals = 6 => price decimals = 18
        uint256 indexPrice = 1e18; // 1$
        uint256 collateralPrice = indexPrice; // long

        // open long position with 1usd x 5
        IncreasePositionResult memory result = position.increase(fee, Side.LONG, 5e24, 1e6, indexPrice, collateralPrice);
        assertEq(position.size, 5e24);
        assertEq(position.collateralValue, 995e21); // take out 1% position fee only
        assertEq(result.feeValue, 5e21);
        assertEq(position.collateralValue + result.feeValue, 1e24);
        console.log("fee", fee.cumulativeInterestRate, fee.lastAccrualTimestamp);

        // increase position with 2usd x 5
        position.increase(fee, Side.LONG, 10e24, 2e6, indexPrice, collateralPrice);
        // position size = 15$ with 3 - (15 * 0.1%) usdc collateral
        // position reserve should be 15
        assertEq(position.size, 15e24);
        assertEq(position.collateralValue, 2985e21);
        assertEq(position.reserveAmount, 15e6);
        assertEq(position.entryPrice, 1e18);

        // ====== when price is up =====
        indexPrice = 11e17; // 1.1$
        collateralPrice = indexPrice;
        // close 5$ = 1/3 position size
        // reserve reduce = 5$, fee = 0.005$ = 0.004545, pnl = 0.5$
        // collateral reduced = 1/3 * 2.985 = 0.995
        // payout = (0.995 + 0.5 - 0.005)$ / 1.1 = 1.354545
        // remaining collateral = 2/3 * origin value = 1.99
        DecreasePositionResult memory decreaseResult = position.decrease(
            fee,
            Side.LONG,
            5e24,
            0, // send 0 and it will calculate reduced collateral
            indexPrice,
            collateralPrice
        );
        // console.log("payout", payout);
        assertEq(decreaseResult.reserveReduced, 5e6);
        assertEq(position.size, 10e24);
        assertEq(decreaseResult.feeValue, 5e21);
        assert(decreaseResult.pnl.sig == POS && decreaseResult.pnl.abs == 5e23);
        assertEq(decreaseResult.payout, 1354545);
        assertEq(position.size, 10e24);
        assertEq(position.collateralValue, 199e22);
        assertEq(position.reserveAmount, 10e6);

        // ====== when price is down =====
        console.log("price down");
        indexPrice = 95e16; // 0.95$
        collateralPrice = indexPrice;

        // close 5$ = 1/2 position size
        // reserve reduce = 5$, fee = 0.005$ = 0.005263, pnl = -0.25$
        // collateral reduced = 1/2 * 1.99 = 0.995
        // payout = (0.995 - 0.25 - 0.005)$ / 0.95 = 0.778947
        // remaining collateral = 2/3 * origin value = 1.99
        decreaseResult = position.decrease(
            fee,
            Side.LONG,
            5e24,
            0, // send 0 and it will calculate reduced collateral
            indexPrice,
            collateralPrice
        );

        // console.log("payout", payout);
        // console.log("reserveReduced", reserveReduced);
        assertEq(decreaseResult.reserveReduced, 5e6);
        assertEq(position.size, 5e24);
        assertEq(decreaseResult.feeValue, 5e21);
        assertEq(decreaseResult.pnl.sig, NEG);
        assertEq(decreaseResult.pnl.abs, 25e22);
        assertEq(decreaseResult.payout, 778947);
        assertEq(position.size, 5e24);
        assertEq(position.collateralValue, 995e21);
        assertEq(position.reserveAmount, 5e6);
    }

    // function testLongPositionWithLost() external {}

    function testShortPosition() external {
        // token decimals = 6 => price decimals = 18
        uint256 indexPrice = 1e18; // 1$
        uint256 collateralPrice = 1e18; // short, collateral is stable coin

        // open short position with 1usd x 5
        IncreasePositionResult memory result = position.increase(fee, Side.SHORT, 5e24, 1e6, indexPrice, collateralPrice);
        assertEq(position.size, 5e24);
        assertEq(position.collateralValue, 995e21); // take out 1% position fee only
        assertEq(result.feeValue, 5e21);
        assertEq(position.collateralValue + result.feeValue, 1e24);

        // increase position with 2usd x 5
        position.increase(fee, Side.SHORT, 10e24, 2e6, indexPrice, collateralPrice);
        // position size = 15$ with 3 - (15 * 0.1%) usdc collateral
        // position reserve should be 15
        assertEq(position.size, 15e24);
        assertEq(position.collateralValue, 2985e21);
        assertEq(position.reserveAmount, 15e6);

        // when price is down
        indexPrice = 9e17; // 0.9$
        // close 5$ = 1/3 position size
        // reserve reduce = 5$, fee = 0.005$, pnl = 0.5$
        // collateral reduced = 1/3 * 2.985 = 0.995
        // payout = (0.995 + 0.5 - 0.005)$ / 1 = 1.49
        // remaining collateral = 2/3 * origin value = 1.99
        DecreasePositionResult memory decreaseResult = position.decrease(
            fee,
            Side.SHORT,
            5e24,
            0, // send 0 and it will calculate reduced collateral
            indexPrice,
            collateralPrice
        );
        assertEq(decreaseResult.reserveReduced, 5e6);
        assertEq(position.size, 10e24);
        assertEq(decreaseResult.feeValue, 5e21);
        assertEq(decreaseResult.pnl.sig, POS);
        assertEq(decreaseResult.pnl.abs, 5e23);
        assertEq(decreaseResult.payout, 1490000);
        assertEq(position.size, 10e24);
        assertEq(position.collateralValue, 199e22);
    }
}
