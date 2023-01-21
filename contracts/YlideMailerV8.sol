// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import './helpers/Owned.sol';
import './helpers/FiduciaryDuty.sol';
import './helpers/BlockNumberRingBufferIndex.sol';

contract YlideMailerV8 is Owned, FiduciaryDuty, BlockNumberRingBufferIndex {

    uint256 public version = 8;

    mapping (uint256 => uint256) public recipientToPushIndex;
    mapping (address => uint256) public senderToBroadcastIndex;

    mapping (uint256 => uint256) public recipientMessagesCount;
    mapping (address => uint256) public broadcastMessagesCount;

    event MailPush(uint256 indexed recipient, address indexed sender, uint256 msgId, uint256 mailList, bytes key);
    event MailContent(uint256 indexed msgId, address indexed sender, uint16 parts, uint16 partIdx, bytes content);
    event MailBroadcast(address indexed sender, uint256 msgId, uint256 mailList);

    function buildHash(address senderAddress, uint256 uniqueId, uint256 time) public pure returns (uint256) {
        return uint256(sha256(bytes.concat(bytes32(uint256(uint160(senderAddress))), bytes32(uniqueId), bytes32(time))));
    }

    /* ----------- MAIL PUSHES ----------- */
    /**
     * sendSmallMail - for sending tiny content to 1 recipient
     * sendBulkMail - for sending tiny content to multiple recipients
     * addMailRecipients - for adding recipients to any message (multipart or not)
     */

    function emitMailPush(uint256 rec, address sender, uint256 msgId, bytes memory key) internal virtual {
        uint256 current = recipientToPushIndex[rec];
        recipientToPushIndex[rec] = storeBlockNumber(current, block.number / 128);
        // write anything to map - 20k gas. think about it
        recipientMessagesCount[rec] += 1;
        emit MailPush(rec, sender, msgId, current, key);
    }

    function sendSmallMail(uint256 uniqueId, uint256 recipient, bytes calldata key, bytes calldata content) public {
        uint256 msgId = buildHash(msg.sender, uniqueId, block.timestamp);

        emit MailContent(msgId, msg.sender, 1, 0, content);
        emitMailPush(recipient, msg.sender, msgId, key);

        payOut(1, 1, 0);
    }

    function sendBulkMail(uint256 uniqueId, uint256[] calldata recipients, bytes[] calldata keys, bytes calldata content) public {
        uint256 msgId = buildHash(msg.sender, uniqueId, uint32(block.timestamp));

        emit MailContent(msgId, msg.sender, 1, 0, content);

        for (uint i = 0; i < recipients.length; i++) {
            emitMailPush(recipients[i], msg.sender, msgId, keys[i]);
        }

        payOut(1, recipients.length, 0);
    }

    function addMailRecipients(uint256 uniqueId, uint256 initTime, uint256[] calldata recipients, bytes[] calldata keys) public {
        uint256 msgId = buildHash(msg.sender, uniqueId, initTime);
        for (uint i = 0; i < recipients.length; i++) {
            emitMailPush(recipients[i], msg.sender, msgId, keys[i]);
        }

        payOut(0, recipients.length, 0);
    }

    /* ---------------------------------------------- */
    /* ------------- MAIL BROADCASTS ---------------- */
    /**
     * sendBroadcast - for sending broadcast content in one transaction
     * sendBroadcastHeader - for emitting broadcast header after uploading all parts of the content
     */

    function emitMailBroadcast(address sender, uint256 msgId) internal virtual {
        uint256 current = senderToBroadcastIndex[sender];
        senderToBroadcastIndex[sender] = storeBlockNumber(current, block.number / 128);
        broadcastMessagesCount[sender] += 1;
        emit MailBroadcast(sender, msgId, current);
    }

    function sendBroadcast(uint256 uniqueId, bytes calldata content) public {
        uint256 msgId = buildHash(msg.sender, uniqueId, block.timestamp);

        emit MailContent(msgId, msg.sender, 1, 0, content);
        emitMailBroadcast(msg.sender, msgId);

        payOut(1, 0, 1);
    }

    function sendBroadcastHeader(uint256 uniqueId, uint256 initTime) public {
        uint256 msgId = buildHash(msg.sender, uniqueId, initTime);
        emitMailBroadcast(msg.sender, msgId);

        payOut(0, 0, 1);
    }

    /* ---------------------------------------------- */

    // For sending content part - for broadcast or not
    function sendMultipartPart(uint256 uniqueId, uint256 initTime, uint16 parts, uint16 partIdx, bytes calldata content) public {
        if (block.timestamp < initTime) {
            revert();
        }
        if (block.timestamp - initTime >= 600) {
            revert();
        }

        uint256 msgId = buildHash(msg.sender, uniqueId, initTime);
        emit MailContent(msgId, msg.sender, parts, partIdx, content);

        payOut(1, 0, 0);
    }
}