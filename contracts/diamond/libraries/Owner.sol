// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Storage} from "../YlideStorage.sol";

library Owner {
	error MustBeContractOwner();

	function enforceIsContractOwner(Storage storage s) internal view {
		if (msg.sender != s.contractOwner) {
			revert MustBeContractOwner();
		}
	}
}
