// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {YlideStorage} from "../storage/YlideStorage.sol";

contract MockMailerFacet is YlideStorage {
	uint256 public constant version = 100;

	function setNewcomerBonus(uint256 bonus) external {
		s.newcomerBonus = bonus;
	}
}
