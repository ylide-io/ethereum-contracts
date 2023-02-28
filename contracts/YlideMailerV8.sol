// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import './helpers/Owned.sol';
import './helpers/Terminatable.sol';
import './helpers/FiduciaryDuty.sol';
import './helpers/BlockNumberRingBufferIndex.sol';

struct BroadcastFeedV8 {
    address owner;
    bool isPublic;
    mapping (address => bool) writers;
    uint256 messagesIndex;
    uint256 messagesCount;
}

// struct MailingThreadV8 {
//     uint256 messagesIndex;
//     uint256 messageCount;

//     mapping (uint256 => bool) recipientParticipationStatus;
// }

struct MailingFeedV8 {
    address owner;
    address payable beneficiary;

    uint256 recipientFee;

    mapping (uint256 => bool) recipientParticipationStatus;

    mapping (uint256 => uint256) recipientToMailIndex;
    mapping (uint256 => uint256) recipientMessagesCount;

    // mapping (uint256 => uint256) recipientToThreadJoinEventsIndex;
    // mapping (uint256 => MailingThreadV8) threads;
}

contract YlideMailerV8 is Owned, Terminatable, FiduciaryDuty, BlockNumberRingBufferIndex {

    uint256 constant public version = 8;

    mapping (uint256 => MailingFeedV8) public mailingFeeds;
    mapping (uint256 => BroadcastFeedV8) public broadcastFeeds;

    mapping (uint256 => uint256) recipientToMailingFeedJoinEventsIndex;

    uint256 public lastFeedId = 1;

    event MailPush(
        uint256 indexed recipient,
        uint256 indexed feedId,
        // uint256 indexed threadId,
        address sender,
        uint256 contentId,
        uint256 previousFeedEventsIndex,
        // uint256 previousThreadEventsIndex,
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
    
    event FeedCreated(uint256 indexed feedId, address indexed creator);
    event FeedOwnershipTransferred(uint256 indexed feedId, address newOwner);
    event FeedBeneficiaryChanged(uint256 indexed feedId, address newBeneficiary);
    
    event FeedPublicityChanged(uint256 indexed feedId, bool isPublic);
    event FeedWriterChange(uint256 indexed feedId, address indexed writer, bool status);

    // event ThreadCreated(uint256 indexed feedId, uint256 indexed threadId, address indexed creator);
    // event ThreadJoined(uint256 indexed feedId, uint256 indexed threadId, uint256 indexed newParticipant, uint256 previousThreadJoinEventsIndex);

    event MailingFeedJoined(uint256 indexed feedId, uint256 indexed newParticipant, uint256 previousFeedJoinEventsIndex);

    constructor() {
        mailingFeeds[0].owner = msg.sender;
        mailingFeeds[0].beneficiary = payable(msg.sender);

        mailingFeeds[1].owner = msg.sender;
        mailingFeeds[1].beneficiary = payable(msg.sender);

        broadcastFeeds[0].owner = msg.sender;
        broadcastFeeds[0].isPublic = false;
        broadcastFeeds[0].writers[msg.sender] = true;

        broadcastFeeds[1].owner = msg.sender;
        broadcastFeeds[1].isPublic = false;
        broadcastFeeds[1].writers[msg.sender] = true;

        broadcastFeeds[2].owner = msg.sender;
        broadcastFeeds[2].isPublic = true;
    }

    function setMailingFeedFees(uint256 feedId, uint256 _recipientFee) public {
        if (msg.sender != mailingFeeds[feedId].owner) {
            revert();
        }
        mailingFeeds[feedId].recipientFee = _recipientFee;
    }

    function isBroadcastFeedWriter(uint256 feedId, address addr) public view returns (bool) {
        return broadcastFeeds[feedId].writers[addr];
    }

    function isMailingFeedRecipient(uint256 feedId, uint256 recipient) public view returns (bool) {
        return mailingFeeds[feedId].recipientParticipationStatus[recipient];
    }

    function getMailingFeedRecipientIndex(uint256 feedId, uint256 recipient) public view returns (uint256) {
        return mailingFeeds[feedId].recipientToMailIndex[recipient];
    }

    function getMailingFeedRecipientMessagesCount(uint256 feedId, uint256 recipient) public view returns (uint256) {
        return mailingFeeds[feedId].recipientMessagesCount[recipient];
    }

    function payOutFeed(uint256 feedId, uint256 recipients) internal virtual {
		uint256 totalValue = mailingFeeds[feedId].recipientFee * recipients;
		if (totalValue > 0) {
			mailingFeeds[feedId].beneficiary.transfer(totalValue);
		}
	}

    function buildContentId(address senderAddress, uint256 uniqueId, uint256 firstBlockNumber, uint256 partsCount, uint256 blockCountLock) public pure returns (uint256) {
        uint256 _hash = uint256(sha256(bytes.concat(bytes32(uint256(uint160(senderAddress))), bytes32(uniqueId), bytes32(firstBlockNumber))));

        uint256 versionMask = (version & 0xFF) * 0x100000000000000000000000000000000000000000000000000000000000000;
        uint256 blockNumberMask = (firstBlockNumber & 0xFFFFFFFF) * 0x1000000000000000000000000000000000000000000000000000000;
        uint256 partsCountMask = (partsCount & 0xFFFF) * 0x100000000000000000000000000000000000000000000000000;
        uint256 blockCountLockMask = (blockCountLock & 0xFFFF) * 0x10000000000000000000000000000000000000000000000;

        uint256 hashMask = _hash & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

        return versionMask | blockNumberMask | partsCountMask | blockCountLockMask | hashMask;
    }

    /* ----------- MAIL PUSHES ----------- */
    /**
     * sendSmallMail - for sending tiny content to 1 recipient
     * sendBulkMail - for sending tiny content to multiple recipients
     * addMailRecipients - for adding recipients to any message (multipart or not)
     */

    function emitMailPush(uint256 feedId, uint256 rec, address sender, uint256 contentId, bytes memory key) internal {
        if (mailingFeeds[feedId].owner == address(0)) {
            revert("Feed does not exist");
        }
        uint256 shrinkedBlock = block.number / 128;
        if (mailingFeeds[feedId].recipientParticipationStatus[rec] == false) {
            mailingFeeds[feedId].recipientParticipationStatus[rec] = true;
            uint256 currentMailingFeedJoinEventsIndex = recipientToMailingFeedJoinEventsIndex[rec];
            recipientToMailingFeedJoinEventsIndex[rec] = storeBlockNumber(currentMailingFeedJoinEventsIndex, shrinkedBlock);
            emit MailingFeedJoined(feedId, rec, currentMailingFeedJoinEventsIndex);
        }
        // if (threadId != 0) {
        //     if (mailingFeeds[feedId].threads[threadId].recipientParticipationStatus[rec] == false) {
        //         mailingFeeds[feedId].threads[threadId].recipientParticipationStatus[rec] = true;
        //         uint256 currentThreadJoinEventsIndex = mailingFeeds[feedId].recipientToThreadJoinEventsIndex[rec];
        //         mailingFeeds[feedId].recipientToThreadJoinEventsIndex[rec] = storeBlockNumber(currentThreadJoinEventsIndex, shrinkedBlock);
        //         emit ThreadJoined(feedId, threadId, rec, currentThreadJoinEventsIndex);
        //     }
        // }
        uint256 currentFeed = mailingFeeds[feedId].recipientToMailIndex[rec];
        mailingFeeds[feedId].recipientToMailIndex[rec] = storeBlockNumber(currentFeed, shrinkedBlock);
        // write anything to map - 20k gas. think about it
        mailingFeeds[feedId].recipientMessagesCount[rec] += 1;
        // uint256 currentThread = 0;
        // if (threadId != 0) {
        //     currentThread = mailingFeeds[feedId].threads[threadId].messagesIndex;
        //     mailingFeeds[feedId].threads[threadId].messagesIndex = storeBlockNumber(currentThread, shrinkedBlock);
        // }
        emit MailPush(rec, feedId, sender, contentId, currentFeed, key);
    }

    function sendSmallMail(uint256 feedId, uint256 uniqueId, uint256 recipient, bytes calldata key, bytes calldata content) public notTerminated returns (uint256) {
        uint256 contentId = buildContentId(msg.sender, uniqueId, block.number, 1, 0);

        emit MessageContent(contentId, msg.sender, 1, 0, content);
        emitMailPush(feedId, recipient, msg.sender, contentId, key);

        payOut(1, 1, 0);
        payOutFeed(feedId, 1);

        return contentId;
    }

    function sendBulkMail(uint256 feedId, uint256 uniqueId, uint256[] calldata recipients, bytes[] calldata keys, bytes calldata content) public notTerminated returns (uint256) {
        uint256 contentId = buildContentId(msg.sender, uniqueId, block.number, 1, 0);

        emit MessageContent(contentId, msg.sender, 1, 0, content);

        for (uint i = 0; i < recipients.length; i++) {
            emitMailPush(feedId, recipients[i], msg.sender, contentId, keys[i]);
        }

        payOut(1, recipients.length, 0);
        payOutFeed(feedId, recipients.length);

        return contentId;
    }

    function addMailRecipients(uint256 feedId, uint256 uniqueId, uint256 firstBlockNumber, uint16 partsCount, uint16 blockCountLock, uint256[] calldata recipients, bytes[] calldata keys) public notTerminated returns (uint256) {
        uint256 contentId = buildContentId(msg.sender, uniqueId, firstBlockNumber, partsCount, blockCountLock);
        for (uint i = 0; i < recipients.length; i++) {
            emitMailPush(feedId, recipients[i], msg.sender, contentId, keys[i]);
        }

        payOut(0, recipients.length, 0);
        payOutFeed(feedId, recipients.length);

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

    function sendBroadcast(uint256 feedId, uint256 uniqueId, bytes calldata content) public notTerminated returns (uint256) {
        if (!broadcastFeeds[feedId].isPublic && broadcastFeeds[feedId].writers[msg.sender] != true) {
            revert('You are not allowed to write to this feed');
        }

        uint256 contentId = buildContentId(msg.sender, uniqueId, block.number, 1, 0);

        emit MessageContent(contentId, msg.sender, 1, 0, content);
        emitBroadcastPush(msg.sender, feedId, contentId);

        payOut(1, 0, 1);

        return contentId;
    }

    function sendBroadcastHeader(uint256 feedId, uint256 uniqueId, uint256 firstBlockNumber, uint16 partsCount, uint16 blockCountLock) public notTerminated returns (uint256) {
        if (!broadcastFeeds[feedId].isPublic && broadcastFeeds[feedId].writers[msg.sender] != true) {
            revert('You are not allowed to write to this feed');
        }

        uint256 contentId = buildContentId(msg.sender, uniqueId, firstBlockNumber, partsCount, blockCountLock);

        emitBroadcastPush(msg.sender, feedId, contentId);

        payOut(0, 0, 1);

        return contentId;
    }

    /* ---------------------------------------------- */

    // For sending content part - for broadcast or not
    function sendMessageContentPart(uint256 uniqueId, uint256 firstBlockNumber, uint256 blockCountLock, uint16 parts, uint16 partIdx, bytes calldata content) public notTerminated returns (uint256) {
        if (block.number < firstBlockNumber) {
            revert('Number less than firstBlockNumber');
        }
        if (block.number - firstBlockNumber >= blockCountLock) {
            revert('Number more than firstBlockNumber + blockCountLock');
        }

        uint256 contentId = buildContentId(msg.sender, uniqueId, firstBlockNumber, parts, blockCountLock);
        emit MessageContent(contentId, msg.sender, parts, partIdx, content);

        payOut(1, 0, 0);

        return contentId;
    }

    /* ---------------------------------------------- */

    // Feed management:
    function createMailingFeed() public returns (uint256) {
        uint256 feedId = uint256(keccak256(abi.encodePacked(address(this), block.number, lastFeedId)));
        lastFeedId += 1;
        
        mailingFeeds[feedId].owner = msg.sender;
        mailingFeeds[feedId].beneficiary = payable(msg.sender);

        payForMailingFeedCreation();

        emit FeedCreated(feedId, msg.sender);

        return feedId;
    }

    function transferMailingFeedOwnership(uint256 feedId, address newOwner) public {
        if (mailingFeeds[feedId].owner != msg.sender) {
            revert('You are not allowed to transfer ownership of this feed');
        }

        mailingFeeds[feedId].owner = newOwner;
        emit FeedOwnershipTransferred(feedId, newOwner);
    }

    function setMailingFeedBeneficiary(uint256 feedId, address payable newBeneficiary) public {
        if (mailingFeeds[feedId].owner != msg.sender) {
            revert('You are not allowed to set beneficiary of this feed');
        }

        mailingFeeds[feedId].beneficiary = newBeneficiary;
        emit FeedBeneficiaryChanged(feedId, newBeneficiary);
    }

    function createBroadcastFeed(bool isPublic) public returns (uint256) {
        uint256 feedId = uint256(keccak256(abi.encodePacked(address(this), block.number, lastFeedId)));
        lastFeedId += 1;
        
        broadcastFeeds[feedId].owner = msg.sender;
        broadcastFeeds[feedId].isPublic = isPublic;
        broadcastFeeds[feedId].writers[msg.sender] = true;
        broadcastFeeds[feedId].messagesIndex = 0;
        broadcastFeeds[feedId].messagesCount = 0;

        payForBroadcastFeedCreation();

        emit FeedCreated(feedId, msg.sender);

        return feedId;
    }

    function transferBroadcastFeedOwnership(uint256 feedId, address newOwner) public {
        if (broadcastFeeds[feedId].owner != msg.sender) {
            revert('You are not allowed to transfer ownership of this feed');
        }

        broadcastFeeds[feedId].owner = newOwner;
        emit FeedOwnershipTransferred(feedId, newOwner);
    }

    function changeBroadcastFeedPublicity(uint256 feedId, bool isPublic) public {
        if (broadcastFeeds[feedId].owner != msg.sender) {
            revert('You are not allowed to change publicity of this feed');
        }

        broadcastFeeds[feedId].isPublic = isPublic;
        emit FeedPublicityChanged(feedId, isPublic);
    }

    function addBroadcastFeedWriter(uint256 feedId, address writer) public {
        if (broadcastFeeds[feedId].owner != msg.sender) {
            revert('You are not allowed to add writers to this feed');
        }

        broadcastFeeds[feedId].writers[writer] = true;
        emit FeedWriterChange(feedId, writer, true);
    }

    function removeBroadcastFeedWriter(uint256 feedId, address writer) public {
        if (broadcastFeeds[feedId].owner != msg.sender) {
            revert('You are not allowed to remove writers from this feed');
        }

        delete broadcastFeeds[feedId].writers[writer];
        emit FeedWriterChange(feedId, writer, false);
    }
}