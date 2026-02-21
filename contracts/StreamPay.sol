// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StreamPayToken is ERC20 {
    constructor(
    ) ERC20("StreamPayToken", "SPT") {
        uint256 _initialBalance = 1_000_000 * 1e18;
        _mint(msg.sender, _initialBalance);
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
