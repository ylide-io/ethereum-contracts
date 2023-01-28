// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import './helpers/Owned.sol';
import './helpers/FiduciaryDuty.sol';
import './helpers/BlockNumberRingBufferIndex.sol';

contract YlideMailerV8 is Owned, FiduciaryDuty, BlockNumberRingBufferIndex {

    uint256 constant public version = 8;

    mapping (uint256 => uint256) public recipientToMailIndex;
    mapping (address => uint256) public senderToBroadcastIndex;

    mapping (uint256 => uint256) public recipientMessagesCount;
    mapping (address => uint256) public broadcastMessagesCount;

    event MailPush(uint256 indexed recipient, address indexed sender, uint256 contentId, uint256 previousEventsIndex, bytes key);
    event BroadcastPush(address indexed sender, uint256 contentId, uint256 previousEventsIndex);
    
    event MessageContent(uint256 indexed contentId, address indexed sender, uint16 parts, uint16 partIdx, bytes content);

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

    function emitMailPush(uint256 rec, address sender, uint256 contentId, bytes memory key) internal {
        uint256 current = recipientToMailIndex[rec];
        recipientToMailIndex[rec] = storeBlockNumber(current, block.number / 128);
        // write anything to map - 20k gas. think about it
        recipientMessagesCount[rec] += 1;
        emit MailPush(rec, sender, contentId, current, key);
    }

    function sendSmallMail(uint256 uniqueId, uint256 recipient, bytes calldata key, bytes calldata content) public returns (uint256) {
        uint256 contentId = buildContentId(msg.sender, uniqueId, block.number, 1, 0);

        emit MessageContent(contentId, msg.sender, 1, 0, content);
        emitMailPush(recipient, msg.sender, contentId, key);

        payOut(1, 1, 0);

        return contentId;
    }

    function sendBulkMail(uint256 uniqueId, uint256[] calldata recipients, bytes[] calldata keys, bytes calldata content) public returns (uint256) {
        uint256 contentId = buildContentId(msg.sender, uniqueId, block.number, 1, 0);

        emit MessageContent(contentId, msg.sender, 1, 0, content);

        for (uint i = 0; i < recipients.length; i++) {
            emitMailPush(recipients[i], msg.sender, contentId, keys[i]);
        }

        payOut(1, recipients.length, 0);

        return contentId;
    }

    function addMailRecipients(uint256 uniqueId, uint256 firstBlockNumber, uint16 partsCount, uint16 blockCountLock, uint256[] calldata recipients, bytes[] calldata keys) public returns (uint256) {
        uint256 contentId = buildContentId(msg.sender, uniqueId, firstBlockNumber, partsCount, blockCountLock);
        for (uint i = 0; i < recipients.length; i++) {
            emitMailPush(recipients[i], msg.sender, contentId, keys[i]);
        }

        payOut(0, recipients.length, 0);

        return contentId;
    }

    /* ---------------------------------------------- */
    /* ------------- MAIL BROADCASTS ---------------- */
    /**
     * sendBroadcast - for sending broadcast content in one transaction
     * sendBroadcastHeader - for emitting broadcast header after uploading all parts of the content
     */

    function emitBroadcastPush(address sender, uint256 contentId) internal {
        uint256 current = senderToBroadcastIndex[sender];
        senderToBroadcastIndex[sender] = storeBlockNumber(current, block.number / 128);
        broadcastMessagesCount[sender] += 1;
        emit BroadcastPush(sender, contentId, current);
    }

    function sendBroadcast(uint256 uniqueId, bytes calldata content) public returns (uint256) {
        uint256 contentId = buildContentId(msg.sender, uniqueId, block.number, 1, 0);

        emit MessageContent(contentId, msg.sender, 1, 0, content);
        emitBroadcastPush(msg.sender, contentId);

        payOut(1, 0, 1);

        return contentId;
    }

    function sendBroadcastHeader(uint256 uniqueId, uint256 firstBlockNumber, uint16 partsCount, uint16 blockCountLock) public returns (uint256) {
        uint256 contentId = buildContentId(msg.sender, uniqueId, firstBlockNumber, partsCount, blockCountLock);
        emitBroadcastPush(msg.sender, contentId);

        payOut(0, 0, 1);

        return contentId;
    }

    /* ---------------------------------------------- */

    // For sending content part - for broadcast or not
    function sendMessageContentPart(uint256 uniqueId, uint256 firstBlockNumber, uint256 blockCountLock, uint16 parts, uint16 partIdx, bytes calldata content) public returns (uint256) {
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
}