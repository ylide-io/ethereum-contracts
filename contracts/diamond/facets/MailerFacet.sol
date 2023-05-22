// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {YlideStorage, StakeInfo} from "../YlideStorage.sol";
import {RingBufferIndex} from "../libraries/RingBufferIndex.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MailerFacet is YlideStorage {
	using SafeERC20 for IERC20;
	uint256 public constant version = 9;

	// ================================
	// ====== Arguments structs =======
	// ================================
	struct MailArgs {
		uint256 recipient;
		address token;
		bytes key;
		// uint8 type - bytes data
		// NONE: 0x
		// SAFE: 1 - uint256 senderSafeChainId, address safeSender, uint256 recipientSafeChainId, address safeRecipient
		bytes supplement;
	}

	// ================================
	// =========== Errors =============
	// ================================
	error FeedDoesNotExist();
	error NumberLessThanFirstBlockNumber();
	error NumberMoreThanFirstBlockNumberPlusBlockCountLock();
	error FeedNotAllowed();
	error FeedExists();
	error PayForAttentionFailed();

	// ================================
	// ===== Internal methods =========
	// ================================

	function _validateBlockLock(uint256 firstBlockNumber, uint256 blockCountLock) internal view {
		if (block.number < firstBlockNumber) {
			revert NumberLessThanFirstBlockNumber();
		}
		if (block.number - firstBlockNumber >= blockCountLock) {
			revert NumberMoreThanFirstBlockNumberPlusBlockCountLock();
		}
	}

	function _validateAccessToBroadcastFeed(bool isPersonal, uint256 feedId) internal view {
		if (
			!isPersonal &&
			!s.broadcastFeeds[feedId].isPublic &&
			s.broadcastIdToWriters[feedId][msg.sender] != true
		) {
			revert FeedNotAllowed();
		}
	}

	function _buildContentId(
		address senderAddress,
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint256 partsCount,
		uint256 blockCountLock
	) internal pure returns (uint256) {
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
	 * sendBulkMail - for sending tiny content to multiple recipients
	 * addMailRecipients - for adding recipients to any message (multipart or not)
	 */
	function _emitMailPush(
		uint256 feedId,
		address sender,
		uint256 contentId,
		MailArgs calldata mailArgs,
		bool paidForAttention
	) internal {
		if (s.mailingFeeds[feedId].owner == address(0)) {
			revert FeedDoesNotExist();
		}
		uint256 shrinkedBlock = block.number / 128;
		if (s.feedIdToRecipientMessagesCount[feedId][mailArgs.recipient] == 0) {
			uint256 currentMailingFeedJoinEventsIndex = s.recipientToMailingFeedJoinEventsIndex[
				mailArgs.recipient
			];
			s.recipientToMailingFeedJoinEventsIndex[mailArgs.recipient] = RingBufferIndex
				.storeBlockNumber(currentMailingFeedJoinEventsIndex, shrinkedBlock);
			emit MailingFeedJoined(feedId, mailArgs.recipient, currentMailingFeedJoinEventsIndex);
		}
		uint256 currentFeed = s.feedIdToRecipientToMailIndex[feedId][mailArgs.recipient];
		s.feedIdToRecipientToMailIndex[feedId][mailArgs.recipient] = RingBufferIndex
			.storeBlockNumber(currentFeed, shrinkedBlock);
		// write anything to map - 20k gas. think about it
		s.feedIdToRecipientMessagesCount[feedId][mailArgs.recipient] += 1;
		emit MailPush(
			mailArgs.recipient,
			feedId,
			sender,
			contentId,
			currentFeed,
			mailArgs.key,
			mailArgs.supplement,
			paidForAttention
		);
	}

	/* ------------- MAIL BROADCASTS ---------------- */
	/**
	 * sendBroadcast - for sending broadcast content in one transaction
	 * sendBroadcastHeader - for emitting broadcast header after uploading all parts of the content
	 */
	function _emitBroadcastPush(address sender, uint256 feedId, uint256 contentId) internal {
		uint256 current = s.broadcastFeeds[feedId].messagesIndex;
		s.broadcastFeeds[feedId].messagesIndex = RingBufferIndex.storeBlockNumber(
			current,
			block.number / 128
		);
		s.broadcastFeeds[feedId].messagesCount += 1;
		emit BroadcastPush(sender, feedId, contentId, current);
	}

	/* ------------- Payout helpers ---------------- */

	function _payOut(uint256 contentParts, uint256 recipients, uint256 broadcasts) internal {
		uint256 totalValue = s.contentPartFee *
			contentParts +
			s.recipientFee *
			recipients +
			s.broadcastFee *
			broadcasts;
		if (totalValue > 0) {
			s.ylideBeneficiary.transfer(totalValue);
		}
	}

	function _payOutMailingFeed(uint256 feedId, uint256 recipients) internal {
		uint256 totalValue = s.mailingFeeds[feedId].recipientFee * recipients;
		if (totalValue > 0) {
			s.mailingFeeds[feedId].beneficiary.transfer(totalValue);
		}
	}

	function _payOutBroadcastFeed(uint256 feedId, uint256 broadcasts) internal {
		uint256 totalValue = s.broadcastFeeds[feedId].broadcastFee * broadcasts;
		if (totalValue > 0) {
			s.broadcastFeeds[feedId].beneficiary.transfer(totalValue);
		}
	}

	function _payForAttention(
		uint256 contentId,
		MailArgs calldata mailArgs
	) internal returns (bool paidForAttention, bool success) {
		// TODO: we should ensure that sending message to yourself is always free
		// white list oneself while setting up the paywall?

		// if protocol has no pay wall tokens - allow sending for free
		if (s.allowedTokens.list.length == 0) {
			return (false, true);
		}
		// if sender is whitelisted - allow sending for free
		if (s.recipientToWhitelistedSender[mailArgs.recipient][msg.sender]) {
			return (false, true);
		}
		// user tries to trick us with wrong token - revert
		if (!s.allowedTokens.includes[mailArgs.token]) {
			return (false, false);
		}

		// if user already paid for this content - revert
		if (s.contentIdToRecipientToStakeInfo[contentId][mailArgs.recipient].token != address(0)) {
			return (false, false);
		}

		uint256 amount;
		uint256 userAmount = s.recipientToPaywallTokenToAmount[mailArgs.recipient][mailArgs.token];
		// if user has no custom paywall
		if (userAmount == 0) {
			uint256 defaultAmount = s.defaultPaywallTokenToAmount[mailArgs.token];
			// if protocol has no default paywall - allow sending for free
			if (defaultAmount == 0) {
				return (false, true);
			}
			// protocol has default paywall - use it
			amount = defaultAmount;
		} else {
			// set user custom paywall
			amount = userAmount;
		}
		uint256 ylideCommission = (s.ylideCommissionPercentage * amount) / 10000;
		uint256 registrarCommission = (s.registrarToCommissionPercentage[
			s.addressToPublicKey[msg.sender].registrar
		] * amount) / 10000;

		s.contentIdToRecipientToStakeInfo[contentId][mailArgs.recipient] = StakeInfo({
			amount: amount,
			token: mailArgs.token,
			sender: msg.sender,
			status: 1,
			stakeBlockedUntil: block.timestamp + s.stakeLockUpPeriod,
			ylideCommission: ylideCommission,
			registrarCommission: registrarCommission
		});
		IERC20(mailArgs.token).safeTransferFrom(
			msg.sender,
			address(this),
			amount + ylideCommission + registrarCommission
		);
		return (true, true);
	}

	// ================================
	// ===== External methods =========
	// ================================

	function sendBulkMail(
		uint256 feedId,
		uint256 uniqueId,
		MailArgs[] calldata args,
		bytes calldata content
	) external payable returns (uint256) {
		uint256 contentId = _buildContentId(msg.sender, uniqueId, block.number, 1, 0);

		emit MessageContent(contentId, msg.sender, 1, 0, content);

		for (uint i = 0; i < args.length; i++) {
			(bool paidForAttention, bool success) = _payForAttention(contentId, args[i]);
			if (!success) {
				revert PayForAttentionFailed();
			}
			_emitMailPush(feedId, msg.sender, contentId, args[i], paidForAttention);
		}

		_payOut(1, args.length, 0);
		_payOutMailingFeed(feedId, args.length);

		return contentId;
	}

	function addMailRecipients(
		uint256 feedId,
		uint256 uniqueId,
		MailArgs[] calldata args,
		uint256 firstBlockNumber,
		uint16 partsCount,
		uint16 blockCountLock
	) external payable returns (uint256) {
		uint256 contentId = _buildContentId(
			msg.sender,
			uniqueId,
			firstBlockNumber,
			partsCount,
			blockCountLock
		);

		for (uint i = 0; i < args.length; i++) {
			(bool paidForAttention, bool success) = _payForAttention(contentId, args[i]);
			if (!success) {
				revert PayForAttentionFailed();
			}
			_emitMailPush(feedId, msg.sender, contentId, args[i], paidForAttention);
		}

		_payOut(0, args.length, 0);
		_payOutMailingFeed(feedId, args.length);

		return contentId;
	}

	function sendBroadcast(
		bool isPersonal,
		uint256 feedId,
		uint256 uniqueId,
		bytes calldata content
	) external payable returns (uint256) {
		_validateAccessToBroadcastFeed(isPersonal, feedId);

		uint256 composedFeedId = isPersonal
			? uint256(sha256(abi.encodePacked(msg.sender, uint256(1), feedId)))
			: feedId;

		uint256 contentId = _buildContentId(msg.sender, uniqueId, block.number, 1, 0);

		emit MessageContent(contentId, msg.sender, 1, 0, content);
		_emitBroadcastPush(msg.sender, composedFeedId, contentId);

		_payOut(1, 0, 1);
		if (!isPersonal) {
			_payOutBroadcastFeed(feedId, 1);
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
	) external payable returns (uint256) {
		_validateAccessToBroadcastFeed(isPersonal, feedId);

		uint256 composedFeedId = isPersonal
			? uint256(sha256(abi.encodePacked(msg.sender, feedId)))
			: feedId;

		uint256 contentId = _buildContentId(
			msg.sender,
			uniqueId,
			firstBlockNumber,
			partsCount,
			blockCountLock
		);

		_emitBroadcastPush(msg.sender, composedFeedId, contentId);

		_payOut(0, 0, 1);
		if (!isPersonal) {
			_payOutBroadcastFeed(feedId, 1);
		}

		return contentId;
	}

	// For sending content part - for broadcast or not
	function sendMessageContentPart(
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint256 blockCountLock,
		uint16 parts,
		uint16 partIdx,
		bytes calldata content
	) external payable returns (uint256) {
		_validateBlockLock(firstBlockNumber, blockCountLock);

		uint256 contentId = _buildContentId(
			msg.sender,
			uniqueId,
			firstBlockNumber,
			parts,
			blockCountLock
		);
		emit MessageContent(contentId, msg.sender, parts, partIdx, content);

		_payOut(1, 0, 0);

		return contentId;
	}

	function createMailingFeed(uint256 uniqueId) external payable returns (uint256) {
		uint256 feedId = uint256(keccak256(abi.encodePacked(msg.sender, uint256(0), uniqueId)));

		if (s.mailingFeeds[feedId].owner != address(0)) {
			revert FeedExists();
		}

		s.mailingFeeds[feedId].owner = msg.sender;
		s.mailingFeeds[feedId].beneficiary = payable(msg.sender);

		if (s.mailingFeedCreationPrice > 0) {
			s.ylideBeneficiary.transfer(s.mailingFeedCreationPrice);
		}

		emit MailingFeedCreated(feedId, msg.sender);

		return feedId;
	}

	function createBroadcastFeed(
		uint256 uniqueId,
		bool isPublic
	) external payable returns (uint256) {
		uint256 feedId = uint256(keccak256(abi.encodePacked(msg.sender, uint256(0), uniqueId)));

		if (s.broadcastFeeds[feedId].owner != address(0)) {
			revert FeedExists();
		}

		s.broadcastFeeds[feedId].owner = msg.sender;
		s.broadcastFeeds[feedId].beneficiary = payable(msg.sender);
		s.broadcastFeeds[feedId].isPublic = isPublic;
		s.broadcastIdToWriters[feedId][msg.sender] = true;
		s.broadcastFeeds[feedId].messagesIndex = 0;
		s.broadcastFeeds[feedId].messagesCount = 0;

		if (s.broadcastFeedCreationPrice > 0) {
			s.ylideBeneficiary.transfer(s.broadcastFeedCreationPrice);
		}

		emit BroadcastFeedCreated(feedId, msg.sender);

		return feedId;
	}
}
