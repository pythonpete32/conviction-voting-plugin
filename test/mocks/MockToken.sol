// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address to
    ) ERC20(name, symbol) {
        _mint(to, initialSupply ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
