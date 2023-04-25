// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IYlideMailer {
	struct RecKeySup {
		uint256 recipient;
		bytes key;
		// uint8 type - bytes data
		// NONE: 0x
		// SAFE: 1 - address safeSender, address safeRecipient
		bytes supplement;
	}

	function sendBulkMail(
		uint256 feedId,
		uint256 uniqueId,
		RecKeySup[] calldata args,
		bytes calldata content
	) external payable returns (uint256);

	function addMailRecipients(
		uint256 feedId,
		uint256 uniqueId,
		RecKeySup[] calldata args,
		uint256 firstBlockNumber,
		uint16 partsCount,
		uint16 blockCountLock
	) external payable returns (uint256);
}
