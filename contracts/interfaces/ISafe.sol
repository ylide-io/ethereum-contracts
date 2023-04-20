// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface ISafe {
	function isOwner(address owner) external view returns (bool);

	function getOwners() external view returns (address[] memory);
}
