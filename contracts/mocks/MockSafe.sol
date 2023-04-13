// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ISafe} from "../interfaces/ISafe.sol";

contract MockSafe is ISafe {
	mapping(address => bool) public owners;

	constructor() {}

	function setOwners(address[] memory _owners, bool[] memory values) external {
		for (uint256 i = 0; i < _owners.length; i++) {
			owners[_owners[i]] = values[i];
		}
	}

	function isOwner(address owner) external view returns (bool) {
		return owners[owner];
	}
}
