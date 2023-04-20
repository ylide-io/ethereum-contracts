// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ISafe} from "../interfaces/ISafe.sol";

contract MockSafe is ISafe {
	mapping(address => bool) public isOwner;
	address[] internal owners;

	constructor() {}

	function setOwners(address[] memory _owners, bool[] memory values) external {
		for (uint256 i = 0; i < _owners.length; i++) {
			isOwner[_owners[i]] = values[i];
			if (values[i]) {
				owners.push(_owners[i]);
			} else {
				for (uint256 j = 0; j < owners.length; j++) {
					if (owners[j] == _owners[i]) {
						owners[j] = owners[owners.length - 1];
						owners.pop();
						break;
					}
				}
			}
		}
	}

	function getOwners() external view returns (address[] memory) {
		return owners;
	}
}
