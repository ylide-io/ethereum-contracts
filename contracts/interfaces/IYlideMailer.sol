// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IYlideMailer {
	struct SendBulkArgs {
		uint256 feedId;
		uint256 uniqueId;
		uint256[] recipients;
		bytes[] keys;
		bytes content;
	}

	struct AddMailRecipientsArgs {
		uint256 feedId;
		uint256 uniqueId;
		uint256 firstBlockNumber;
		uint16 partsCount;
		uint16 blockCountLock;
		uint256[] recipients;
		bytes[] keys;
	}

	struct SignatureArgs {
		bytes signature;
		uint256 nonce;
		uint256 deadline;
		address sender;
	}

	function sendBulkMail(
		SendBulkArgs calldata args,
		SignatureArgs calldata signatureArgs
	) external payable returns (uint256);

	function addMailRecipients(
		AddMailRecipientsArgs calldata args,
		SignatureArgs calldata signatureArgs
	) external payable returns (uint256);
}
