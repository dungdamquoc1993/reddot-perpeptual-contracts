pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {SignedInt, SignedIntOps} from "../src/lib/SignedInt.sol";

contract SignedIntTest is Test {
    using SignedIntOps for SignedInt;

    function testWrap() external {
        assertEq(SignedIntOps.wrap(uint256(0)).eq(uint(0)), true);
        assertEq(SignedIntOps.wrap(int256(0)).eq(uint256(0)), true);
    }

    function testMul() external {
        SignedInt memory _1 = SignedIntOps.wrap(uint(1));
        SignedInt memory _5 = SignedIntOps.wrap(uint(5));
        SignedInt memory _0 = SignedIntOps.wrap(uint(0));
        SignedInt memory neg1 = SignedIntOps.wrap(int(-1));
        SignedInt memory neg5 = SignedIntOps.wrap(int(-5));
        SignedInt memory neg2 = SignedIntOps.wrap(int(-2));

        assertTrue(_1.mul(_5).eq(uint(5)));
        assertTrue(neg1.mul(neg5).eq(uint(5)));
        assertTrue(neg1.mul(_5).eq(int(-5)));
        assertTrue(neg2.mul(neg5).eq(int(10)));
        assertTrue(_0.mul(neg5).eq(uint(0)));
        assertTrue(_0.mul(_5).eq(uint(0)));
    }
}
