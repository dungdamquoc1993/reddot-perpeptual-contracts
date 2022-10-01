// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PerpToken is ERC20 {
    address public minter;

    uint256 public constant MAX_TOTAL_SUPPLY = 1_000_000_000 ether;

    constructor() ERC20("Perpetual Governance Token", "PERP") {}

    function setMinter(address _minter) external {
        require(minter == address(0), "PerpToken::minterAlreadySet");
        minter = _minter;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "PerpToken::!minter");
        _mint(to, amount);
        require(MAX_TOTAL_SUPPLY >= totalSupply(), "PerpToken::!max totalSupply");
    }
}
