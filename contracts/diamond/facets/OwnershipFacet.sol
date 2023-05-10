// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {YlideStorage} from "../storage/YlideStorage.sol";
import {LibOwner} from "../libraries/LibOwner.sol";
import {IERC173} from "../interfaces/IERC173.sol";

contract OwnershipFacet is YlideStorage, IERC173 {
	function transferOwnership(address _newOwner) external override {
		LibOwner.enforceIsContractOwner(s);
		LibOwner.setContractOwner(s, _newOwner);
	}

	function owner() external view override returns (address owner_) {
		owner_ = LibOwner.contractOwner(s);
	}
}
