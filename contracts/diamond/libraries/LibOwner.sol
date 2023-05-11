// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {DiamondStorage} from "../storage/DiamondStorage.sol";

library LibOwner {
	event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
	error MustBeContractOwner();

	function setContractOwner(DiamondStorage storage s, address _newOwner) internal {
		address previousOwner = s.contractOwner;
		s.contractOwner = _newOwner;
		emit OwnershipTransferred(previousOwner, _newOwner);
	}

	function contractOwner(DiamondStorage storage s) internal view returns (address) {
		return s.contractOwner;
	}

	function enforceIsContractOwner(DiamondStorage storage s) internal view {
		if (msg.sender != s.contractOwner) {
			revert MustBeContractOwner();
		}
	}
}
