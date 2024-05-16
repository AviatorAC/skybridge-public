// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TST") {
        // Mint 1 million tokens to the contract creator
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    function test() public {}
}
