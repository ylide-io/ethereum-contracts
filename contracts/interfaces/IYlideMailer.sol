// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IYlideMailer {
	function sendBulkMail(
		address sender,
		uint256 feedId,
		uint256 uniqueId,
		uint256[] calldata recipients,
		bytes[] calldata keys,
		bytes calldata content
	) external payable returns (uint256);

	function addMailRecipients(
		address sender,
		uint256 feedId,
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint16 partsCount,
		uint16 blockCountLock,
		uint256[] calldata recipients,
		bytes[] calldata keys
	) external payable returns (uint256);
}
