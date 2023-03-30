// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
	constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

	function mint(uint256 amount) external {
		_mint(msg.sender, amount);
	}
}
