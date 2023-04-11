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

	function getStorageAt(uint256, uint256) external view returns (bytes memory) {
		return new bytes(0);
	}

	function VERSION() external view returns (string memory) {
		return "1.1.1";
	}
}
