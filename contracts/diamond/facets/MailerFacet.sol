// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {YlideStorage} from "../storage/YlideStorage.sol";
import {LibRingBufferIndex} from "../libraries/LibRingBufferIndex.sol";

contract MailerFacet is YlideStorage {
	uint256 public constant version = 9;

	error FeedDoesNotExist();
	error NumberLessThanFirstBlockNumber();
	error NumberMoreThanFirstBlockNumberPlusBlockCountLock();
	error FeedNotAllowed();

	struct RecKeySup {
		uint256 recipient;
		bytes key;
		// uint8 type - bytes data
		// NONE: 0x
		// SAFE: 1 - uint256 senderSafeChainId, address safeSender, uint256 recipientSafeChainId, address safeRecipient
		bytes supplement;
	}

	function validateBlockLock(uint256 firstBlockNumber, uint256 blockCountLock) internal view {
		if (block.number < firstBlockNumber) {
			revert NumberLessThanFirstBlockNumber();
		}
		if (block.number - firstBlockNumber >= blockCountLock) {
			revert NumberMoreThanFirstBlockNumberPlusBlockCountLock();
		}
	}

	function validateAccessToBroadcastFeed(bool isPersonal, uint256 feedId) internal view {
		if (
			!isPersonal &&
			!s.broadcastFeeds[feedId].isPublic &&
			s.broadcastIdToWriters[feedId][msg.sender] != true
		) {
			revert FeedNotAllowed();
		}
	}

	function buildContentId(
		address senderAddress,
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint256 partsCount,
		uint256 blockCountLock
	) public pure returns (uint256) {
		uint256 _hash = uint256(
			sha256(
				bytes.concat(
					bytes32(uint256(uint160(senderAddress))),
					bytes32(uniqueId),
					bytes32(firstBlockNumber)
				)
			)
		);

		uint256 versionMask = (version & 0xFF) *
			0x100000000000000000000000000000000000000000000000000000000000000;
		uint256 blockNumberMask = (firstBlockNumber & 0xFFFFFFFF) *
			0x1000000000000000000000000000000000000000000000000000000;
		uint256 partsCountMask = (partsCount & 0xFFFF) *
			0x100000000000000000000000000000000000000000000000000;
		uint256 blockCountLockMask = (blockCountLock & 0xFFFF) *
			0x10000000000000000000000000000000000000000000000;

		uint256 hashMask = _hash & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

		return versionMask | blockNumberMask | partsCountMask | blockCountLockMask | hashMask;
	}

	/* ----------- MAIL PUSHES ----------- */
	/**
	 * sendSmallMail - for sending tiny content to 1 recipient
	 * sendBulkMail - for sending tiny content to multiple recipients
	 * addMailRecipients - for adding recipients to any message (multipart or not)
	 */

	function emitMailPush(
		uint256 feedId,
		address sender,
		uint256 contentId,
		RecKeySup calldata recKeySup
	) internal {
		if (s.mailingFeeds[feedId].owner == address(0)) {
			revert FeedDoesNotExist();
		}
		uint256 shrinkedBlock = block.number / 128;
		if (s.feedIdToRecipientMessagesCount[feedId][recKeySup.recipient] == 0) {
			uint256 currentMailingFeedJoinEventsIndex = s.recipientToMailingFeedJoinEventsIndex[
				recKeySup.recipient
			];
			s.recipientToMailingFeedJoinEventsIndex[recKeySup.recipient] = LibRingBufferIndex
				.storeBlockNumber(currentMailingFeedJoinEventsIndex, shrinkedBlock);
			emit MailingFeedJoined(feedId, recKeySup.recipient, currentMailingFeedJoinEventsIndex);
		}
		uint256 currentFeed = s.feedIdToRecipientToMailIndex[feedId][recKeySup.recipient];
		s.feedIdToRecipientToMailIndex[feedId][recKeySup.recipient] = LibRingBufferIndex
			.storeBlockNumber(currentFeed, shrinkedBlock);
		// write anything to map - 20k gas. think about it
		s.feedIdToRecipientMessagesCount[feedId][recKeySup.recipient] += 1;
		emit MailPush(
			recKeySup.recipient,
			feedId,
			sender,
			contentId,
			currentFeed,
			recKeySup.key,
			recKeySup.supplement
		);
	}

	function sendBulkMail(
		uint256 feedId,
		uint256 uniqueId,
		RecKeySup[] calldata args,
		bytes calldata content
	) external payable returns (uint256) {
		uint256 contentId = buildContentId(msg.sender, uniqueId, block.number, 1, 0);

		emit MessageContent(contentId, msg.sender, 1, 0, content);

		for (uint i = 0; i < args.length; i++) {
			emitMailPush(feedId, msg.sender, contentId, args[i]);
		}

		payOut(1, args.length, 0);
		payOutMailingFeed(feedId, args.length);

		return contentId;
	}

	function addMailRecipients(
		uint256 feedId,
		uint256 uniqueId,
		RecKeySup[] calldata args,
		uint256 firstBlockNumber,
		uint16 partsCount,
		uint16 blockCountLock
	) external payable returns (uint256) {
		uint256 contentId = buildContentId(
			msg.sender,
			uniqueId,
			firstBlockNumber,
			partsCount,
			blockCountLock
		);
		for (uint i = 0; i < args.length; i++) {
			emitMailPush(feedId, msg.sender, contentId, args[i]);
		}

		payOut(0, args.length, 0);
		payOutMailingFeed(feedId, args.length);

		return contentId;
	}

	/* ---------------------------------------------- */
	/* ------------- MAIL BROADCASTS ---------------- */
	/**
	 * sendBroadcast - for sending broadcast content in one transaction
	 * sendBroadcastHeader - for emitting broadcast header after uploading all parts of the content
	 */

	function emitBroadcastPush(address sender, uint256 feedId, uint256 contentId) internal {
		uint256 current = s.broadcastFeeds[feedId].messagesIndex;
		s.broadcastFeeds[feedId].messagesIndex = LibRingBufferIndex.storeBlockNumber(
			current,
			block.number / 128
		);
		s.broadcastFeeds[feedId].messagesCount += 1;
		emit BroadcastPush(sender, feedId, contentId, current);
	}

	function sendBroadcast(
		bool isPersonal,
		uint256 feedId,
		uint256 uniqueId,
		bytes calldata content
	) public payable returns (uint256) {
		validateAccessToBroadcastFeed(isPersonal, feedId);

		uint256 composedFeedId = isPersonal
			? uint256(sha256(abi.encodePacked(msg.sender, uint256(1), feedId)))
			: feedId;

		uint256 contentId = buildContentId(msg.sender, uniqueId, block.number, 1, 0);

		emit MessageContent(contentId, msg.sender, 1, 0, content);
		emitBroadcastPush(msg.sender, composedFeedId, contentId);

		payOut(1, 0, 1);
		if (!isPersonal) {
			payOutBroadcastFeed(feedId, 1);
		}

		return contentId;
	}

	function sendBroadcastHeader(
		bool isPersonal,
		uint256 feedId,
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint16 partsCount,
		uint16 blockCountLock
	) public payable returns (uint256) {
		validateAccessToBroadcastFeed(isPersonal, feedId);

		uint256 composedFeedId = isPersonal
			? uint256(sha256(abi.encodePacked(msg.sender, feedId)))
			: feedId;

		uint256 contentId = buildContentId(
			msg.sender,
			uniqueId,
			firstBlockNumber,
			partsCount,
			blockCountLock
		);

		emitBroadcastPush(msg.sender, composedFeedId, contentId);

		payOut(0, 0, 1);
		if (!isPersonal) {
			payOutBroadcastFeed(feedId, 1);
		}

		return contentId;
	}

	/* ---------------------------------------------- */

	// For sending content part - for broadcast or not
	function sendMessageContentPart(
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint256 blockCountLock,
		uint16 parts,
		uint16 partIdx,
		bytes calldata content
	) public payable returns (uint256) {
		validateBlockLock(firstBlockNumber, blockCountLock);

		uint256 contentId = buildContentId(
			msg.sender,
			uniqueId,
			firstBlockNumber,
			parts,
			blockCountLock
		);
		emit MessageContent(contentId, msg.sender, parts, partIdx, content);

		payOut(1, 0, 0);

		return contentId;
	}

	function payOut(uint256 contentParts, uint256 recipients, uint256 broadcasts) internal virtual {
		uint256 totalValue = s.contentPartFee *
			contentParts +
			s.recipientFee *
			recipients +
			s.broadcastFee *
			broadcasts;
		if (totalValue > 0) {
			s.beneficiary.transfer(totalValue);
		}
	}

	function payOutMailingFeed(uint256 feedId, uint256 recipients) internal virtual {
		uint256 totalValue = s.mailingFeeds[feedId].recipientFee * recipients;
		if (totalValue > 0) {
			s.mailingFeeds[feedId].beneficiary.transfer(totalValue);
		}
	}

	function payOutBroadcastFeed(uint256 feedId, uint256 broadcasts) internal virtual {
		uint256 totalValue = s.broadcastFeeds[feedId].broadcastFee * broadcasts;
		if (totalValue > 0) {
			s.broadcastFeeds[feedId].beneficiary.transfer(totalValue);
		}
	}
}
