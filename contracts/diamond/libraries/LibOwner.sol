// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {DiamondStorage} from "../storage/DiamondStorage.sol";

library LibOwner {
	error MustBeContractOwner();

	function enforceIsContractOwner(DiamondStorage storage s) internal view {
		if (msg.sender != s.contractOwner) {
			revert MustBeContractOwner();
		}
	}
}
