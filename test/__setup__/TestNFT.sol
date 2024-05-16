// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract TestNFT is ERC721 {
	constructor() ERC721("Test NFT", "TNFT") {
		// Mint 1 NFT to the contract creator
		_mint(msg.sender, 1);
	}

	function test() public {}
}
