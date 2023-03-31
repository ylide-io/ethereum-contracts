// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
	constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

	function mint(uint256 tokenId) external {
		_mint(msg.sender, tokenId);
	}
}
