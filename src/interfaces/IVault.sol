// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

interface IVault {
    function withdrawFee(address _token, address _recipient) external;

    function whitelistedTokens(address _token) external returns (bool);
}
