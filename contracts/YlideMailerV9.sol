// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Owned} from "./helpers/Owned.sol";
import {Terminatable} from "./helpers/Terminatable.sol";
import {FiduciaryDuty} from "./helpers/FiduciaryDuty.sol";
import {BlockNumberRingBufferIndex} from "./helpers/BlockNumberRingBufferIndex.sol";

import {IYlideMailer} from "./interfaces/IYlideMailer.sol";

contract YlideMailerV9 is
	Owned,
	Terminatable,
	FiduciaryDuty,
	BlockNumberRingBufferIndex,
	IYlideMailer
{
	uint256 public constant version = 9;

	mapping(uint256 => MailingFeedV9) public mailingFeeds;
	mapping(uint256 => BroadcastFeedV9) public broadcastFeeds;

	mapping(uint256 => uint256) public recipientToMailingFeedJoinEventsIndex;

	address public ylidePay;

	struct BroadcastFeedV9 {
		address owner;
		address payable beneficiary;
		uint256 broadcastFee;
		bool isPublic;
		mapping(address => bool) writers;
		uint256 messagesIndex;
		uint256 messagesCount;
	}

	struct MailingFeedV9 {
		address owner;
		address payable beneficiary;
		uint256 recipientFee;
		mapping(uint256 => uint256) recipientToMailIndex;
		mapping(uint256 => uint256) recipientMessagesCount;
	}

	struct Recipient {
		uint256 user;
		address token;
		uint256 amount;
		TokenType tokenType;
	}

	enum TokenType {
		ERC20,
		ERC721
	}

	event MailPush(
		uint256 indexed recipient,
		uint256 indexed feedId,
		address sender,
		uint256 contentId,
		uint256 previousFeedEventsIndex,
		bytes key
	);
	event BroadcastPush(
		address indexed sender,
		uint256 indexed feedId,
		uint256 contentId,
		uint256 previousFeedEventsIndex
	);

	event MessageContent(
		uint256 indexed contentId,
		address indexed sender,
		uint16 parts,
		uint16 partIdx,
		bytes content
	);

	event MailingFeedCreated(uint256 indexed feedId, address indexed creator);
	event BroadcastFeedCreated(uint256 indexed feedId, address indexed creator);

	event MailingFeedOwnershipTransferred(uint256 indexed feedId, address newOwner);
	event BroadcastFeedOwnershipTransferred(uint256 indexed feedId, address newOwner);

	event MailingFeedBeneficiaryChanged(uint256 indexed feedId, address newBeneficiary);
	event BroadcastFeedBeneficiaryChanged(uint256 indexed feedId, address newBeneficiary);

	event BroadcastFeedPublicityChanged(uint256 indexed feedId, bool isPublic);
	event BroadcastFeedWriterChange(uint256 indexed feedId, address indexed writer, bool status);

	event MailingFeedJoined(
		uint256 indexed feedId,
		uint256 indexed newParticipant,
		uint256 previousFeedJoinEventsIndex
	);

	constructor() {
		mailingFeeds[0].owner = msg.sender; // regular mail
		mailingFeeds[0].beneficiary = payable(msg.sender);

		mailingFeeds[1].owner = msg.sender; // otc mail
		mailingFeeds[1].beneficiary = payable(msg.sender);

		mailingFeeds[2].owner = msg.sender; // system messages
		mailingFeeds[2].beneficiary = payable(msg.sender);

		mailingFeeds[3].owner = msg.sender; // system messages
		mailingFeeds[3].beneficiary = payable(msg.sender);

		mailingFeeds[4].owner = msg.sender; // system messages
		mailingFeeds[4].beneficiary = payable(msg.sender);

		mailingFeeds[5].owner = msg.sender; // system messages
		mailingFeeds[5].beneficiary = payable(msg.sender);

		mailingFeeds[6].owner = msg.sender; // system messages
		mailingFeeds[6].beneficiary = payable(msg.sender);

		mailingFeeds[7].owner = msg.sender; // system messages
		mailingFeeds[7].beneficiary = payable(msg.sender);

		mailingFeeds[8].owner = msg.sender; // system messages
		mailingFeeds[8].beneficiary = payable(msg.sender);

		mailingFeeds[9].owner = msg.sender; // system messages
		mailingFeeds[9].beneficiary = payable(msg.sender);

		mailingFeeds[10].owner = msg.sender; // system messages
		mailingFeeds[10].beneficiary = payable(msg.sender);

		broadcastFeeds[0].owner = msg.sender;
		broadcastFeeds[0].beneficiary = payable(msg.sender);
		broadcastFeeds[0].isPublic = false;
		broadcastFeeds[0].writers[msg.sender] = true;

		broadcastFeeds[1].owner = msg.sender;
		broadcastFeeds[1].beneficiary = payable(msg.sender);
		broadcastFeeds[1].isPublic = false;
		broadcastFeeds[1].writers[msg.sender] = true;

		broadcastFeeds[2].owner = msg.sender;
		broadcastFeeds[2].beneficiary = payable(msg.sender);
		broadcastFeeds[2].isPublic = true;
	}

	function setMailingFeedFees(uint256 feedId, uint256 _recipientFee) public {
		if (msg.sender != mailingFeeds[feedId].owner) {
			revert();
		}
		mailingFeeds[feedId].recipientFee = _recipientFee;
	}

	function setBroadcastFeedFees(uint256 feedId, uint256 _broadcastFee) public {
		if (msg.sender != broadcastFeeds[feedId].owner) {
			revert();
		}
		broadcastFeeds[feedId].broadcastFee = _broadcastFee;
	}

	function setYlidePay(address _ylidePay) external onlyOwner {
		ylidePay = _ylidePay;
	}

	function isBroadcastFeedWriter(uint256 feedId, address addr) public view returns (bool) {
		return broadcastFeeds[feedId].writers[addr];
	}

	function getMailingFeedRecipientIndex(
		uint256 feedId,
		uint256 recipient
	) public view returns (uint256) {
		return mailingFeeds[feedId].recipientToMailIndex[recipient];
	}

	function getMailingFeedRecipientMessagesCount(
		uint256 feedId,
		uint256 recipient
	) public view returns (uint256) {
		return mailingFeeds[feedId].recipientMessagesCount[recipient];
	}

	function payOutMailingFeed(uint256 feedId, uint256 recipients) internal virtual {
		uint256 totalValue = mailingFeeds[feedId].recipientFee * recipients;
		if (totalValue > 0) {
			mailingFeeds[feedId].beneficiary.transfer(totalValue);
		}
	}

	function payOutBroadcastFeed(uint256 feedId, uint256 broadcasts) internal virtual {
		uint256 totalValue = broadcastFeeds[feedId].broadcastFee * broadcasts;
		if (totalValue > 0) {
			broadcastFeeds[feedId].beneficiary.transfer(totalValue);
		}
	}

	receive() external payable {
		// do nothing
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
	 * sendBulkMail - for sending tiny content to multiple recipients
	 * addMailRecipients - for adding recipients to any message (multipart or not)
	 */

	function emitMailPush(
		uint256 feedId,
		uint256 rec,
		address sender,
		uint256 contentId,
		bytes memory key
	) internal {
		if (mailingFeeds[feedId].owner == address(0)) {
			revert("Feed does not exist");
		}
		uint256 shrinkedBlock = block.number / 128;
		if (mailingFeeds[feedId].recipientMessagesCount[rec] == 0) {
			uint256 currentMailingFeedJoinEventsIndex = recipientToMailingFeedJoinEventsIndex[rec];
			recipientToMailingFeedJoinEventsIndex[rec] = storeBlockNumber(
				currentMailingFeedJoinEventsIndex,
				shrinkedBlock
			);
			emit MailingFeedJoined(feedId, rec, currentMailingFeedJoinEventsIndex);
		}
		uint256 currentFeed = mailingFeeds[feedId].recipientToMailIndex[rec];
		mailingFeeds[feedId].recipientToMailIndex[rec] = storeBlockNumber(
			currentFeed,
			shrinkedBlock
		);
		// write anything to map - 20k gas. think about it
		mailingFeeds[feedId].recipientMessagesCount[rec] += 1;
		emit MailPush(rec, feedId, sender, contentId, currentFeed, key);
	}

	function sendBulkMail(
		uint256 feedId,
		uint256 uniqueId,
		uint256[] calldata recipients,
		bytes[] calldata keys,
		bytes calldata content
	) public payable notTerminated returns (uint256) {
		return _sendBulkMail(msg.sender, feedId, uniqueId, recipients, keys, content);
	}

	function sendBulkMail(
		address sender,
		uint256 feedId,
		uint256 uniqueId,
		uint256[] calldata recipients,
		bytes[] calldata keys,
		bytes calldata content
	) public payable notTerminated returns (uint256) {
		if (msg.sender != ylidePay) {
			revert("Caller is not YlidePay");
		}
		return _sendBulkMail(sender, feedId, uniqueId, recipients, keys, content);
	}

	function _sendBulkMail(
		address sender,
		uint256 feedId,
		uint256 uniqueId,
		uint256[] calldata recipients,
		bytes[] calldata keys,
		bytes calldata content
	) internal notTerminated returns (uint256) {
		uint256 contentId = buildContentId(sender, uniqueId, block.number, 1, 0);

		emit MessageContent(contentId, sender, 1, 0, content);

		for (uint i = 0; i < recipients.length; i++) {
			emitMailPush(feedId, recipients[i], sender, contentId, keys[i]);
		}

		payOut(1, recipients.length, 0);
		payOutMailingFeed(feedId, recipients.length);

		return contentId;
	}

	function addMailRecipients(
		uint256 feedId,
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint16 partsCount,
		uint16 blockCountLock,
		uint256[] calldata recipients,
		bytes[] calldata keys
	) public payable notTerminated returns (uint256) {
		return
			_addMailRecipients(
				msg.sender,
				feedId,
				uniqueId,
				firstBlockNumber,
				partsCount,
				blockCountLock,
				recipients,
				keys
			);
	}

	function addMailRecipients(
		address sender,
		uint256 feedId,
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint16 partsCount,
		uint16 blockCountLock,
		uint256[] calldata recipients,
		bytes[] calldata keys
	) public payable notTerminated returns (uint256) {
		if (msg.sender != ylidePay) {
			revert("Caller is not ylidePay");
		}
		return
			_addMailRecipients(
				sender,
				feedId,
				uniqueId,
				firstBlockNumber,
				partsCount,
				blockCountLock,
				recipients,
				keys
			);
	}

	function _addMailRecipients(
		address sender,
		uint256 feedId,
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint16 partsCount,
		uint16 blockCountLock,
		uint256[] calldata recipients,
		bytes[] calldata keys
	) internal returns (uint256) {
		uint256 contentId = buildContentId(
			sender,
			uniqueId,
			firstBlockNumber,
			partsCount,
			blockCountLock
		);
		for (uint i = 0; i < recipients.length; i++) {
			emitMailPush(feedId, recipients[i], sender, contentId, keys[i]);
		}

		payOut(0, recipients.length, 0);
		payOutMailingFeed(feedId, recipients.length);

		return contentId;
	}

	/* ---------------------------------------------- */
	/* ------------- MAIL BROADCASTS ---------------- */
	/**
	 * sendBroadcast - for sending broadcast content in one transaction
	 * sendBroadcastHeader - for emitting broadcast header after uploading all parts of the content
	 */

	function emitBroadcastPush(address sender, uint256 feedId, uint256 contentId) internal {
		uint256 current = broadcastFeeds[feedId].messagesIndex;
		broadcastFeeds[feedId].messagesIndex = storeBlockNumber(current, block.number / 128);
		broadcastFeeds[feedId].messagesCount += 1;
		emit BroadcastPush(sender, feedId, contentId, current);
	}

	function sendBroadcast(
		bool isPersonal,
		uint256 feedId,
		uint256 uniqueId,
		bytes calldata content
	) public payable notTerminated returns (uint256) {
		if (
			!isPersonal &&
			!broadcastFeeds[feedId].isPublic &&
			broadcastFeeds[feedId].writers[msg.sender] != true
		) {
			revert("You are not allowed to write to this feed");
		}

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
	) public payable notTerminated returns (uint256) {
		if (
			!isPersonal &&
			!broadcastFeeds[feedId].isPublic &&
			broadcastFeeds[feedId].writers[msg.sender] != true
		) {
			revert("You are not allowed to write to this feed");
		}

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
	) public payable notTerminated returns (uint256) {
		if (block.number < firstBlockNumber) {
			revert("Number less than firstBlockNumber");
		}
		if (block.number - firstBlockNumber >= blockCountLock) {
			revert("Number more than firstBlockNumber + blockCountLock");
		}

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

	/* ---------------------------------------------- */

	// Feed management:
	function createMailingFeed(uint256 uniqueId) public payable returns (uint256) {
		uint256 feedId = uint256(keccak256(abi.encodePacked(msg.sender, uint256(0), uniqueId)));

		if (mailingFeeds[feedId].owner != address(0)) {
			revert("Feed already exists");
		}

		mailingFeeds[feedId].owner = msg.sender;
		mailingFeeds[feedId].beneficiary = payable(msg.sender);

		payForMailingFeedCreation();

		emit MailingFeedCreated(feedId, msg.sender);

		return feedId;
	}

	function transferMailingFeedOwnership(uint256 feedId, address newOwner) public {
		if (mailingFeeds[feedId].owner != msg.sender) {
			revert("You are not allowed to transfer ownership of this feed");
		}

		mailingFeeds[feedId].owner = newOwner;
		emit MailingFeedOwnershipTransferred(feedId, newOwner);
	}

	function setMailingFeedBeneficiary(uint256 feedId, address payable newBeneficiary) public {
		if (mailingFeeds[feedId].owner != msg.sender) {
			revert("You are not allowed to set beneficiary of this feed");
		}

		mailingFeeds[feedId].beneficiary = newBeneficiary;
		emit MailingFeedBeneficiaryChanged(feedId, newBeneficiary);
	}

	function createBroadcastFeed(uint256 uniqueId, bool isPublic) public payable returns (uint256) {
		uint256 feedId = uint256(keccak256(abi.encodePacked(msg.sender, uint256(0), uniqueId)));

		if (broadcastFeeds[feedId].owner != address(0)) {
			revert("Feed already exists");
		}

		broadcastFeeds[feedId].owner = msg.sender;
		broadcastFeeds[feedId].beneficiary = payable(msg.sender);
		broadcastFeeds[feedId].isPublic = isPublic;
		broadcastFeeds[feedId].writers[msg.sender] = true;
		broadcastFeeds[feedId].messagesIndex = 0;
		broadcastFeeds[feedId].messagesCount = 0;

		payForBroadcastFeedCreation();

		emit BroadcastFeedCreated(feedId, msg.sender);

		return feedId;
	}

	function transferBroadcastFeedOwnership(uint256 feedId, address newOwner) public {
		if (broadcastFeeds[feedId].owner != msg.sender) {
			revert("You are not allowed to transfer ownership of this feed");
		}

		broadcastFeeds[feedId].owner = newOwner;
		emit BroadcastFeedOwnershipTransferred(feedId, newOwner);
	}

	function setBroadcastFeedBeneficiary(uint256 feedId, address payable newBeneficiary) public {
		if (broadcastFeeds[feedId].owner != msg.sender) {
			revert("You are not allowed to set beneficiary of this feed");
		}

		broadcastFeeds[feedId].beneficiary = newBeneficiary;
		emit BroadcastFeedBeneficiaryChanged(feedId, newBeneficiary);
	}

	function changeBroadcastFeedPublicity(uint256 feedId, bool isPublic) public {
		if (broadcastFeeds[feedId].owner != msg.sender) {
			revert("You are not allowed to change publicity of this feed");
		}

		broadcastFeeds[feedId].isPublic = isPublic;
		emit BroadcastFeedPublicityChanged(feedId, isPublic);
	}

	function addBroadcastFeedWriter(uint256 feedId, address writer) public {
		if (broadcastFeeds[feedId].owner != msg.sender) {
			revert("You are not allowed to add writers to this feed");
		}

		broadcastFeeds[feedId].writers[writer] = true;
		emit BroadcastFeedWriterChange(feedId, writer, true);
	}

	function removeBroadcastFeedWriter(uint256 feedId, address writer) public {
		if (broadcastFeeds[feedId].owner != msg.sender) {
			revert("You are not allowed to remove writers from this feed");
		}

		delete broadcastFeeds[feedId].writers[writer];
		emit BroadcastFeedWriterChange(feedId, writer, false);
	}
}