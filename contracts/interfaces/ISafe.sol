// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface ISafe {
	function isOwner(address owner) external view returns (bool);

	function getStorageAt(uint256 offset, uint256 length) external view returns (bytes memory);

	function VERSION() external view returns (string memory);
}
