// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Owned} from "./helpers/Owned.sol";

import {IYlideMailer} from "./interfaces/IYlideMailer.sol";
import {ISablier} from "./interfaces/ISablier.sol";
import {IYlideTokenAttachment} from "./interfaces/IYlideTokenAttachment.sol";

contract YlideStreamSablierV1 is IYlideTokenAttachment, Owned, Pausable {
	using SafeERC20 for IERC20;

	// ===================
	// ===== Structs =====
	// ===================
	struct StreamArgs {
		uint256 startTime;
		uint256 stopTime;
		uint256 deposit;
		address tokenAddress;
		address recipient;
	}

	struct StreamCancelArgs {
		uint256 senderReceived;
		uint256 recipientReceived;
		bool success;
	}

	struct Withdrawal {
		uint256 amount;
		uint256 timestamp;
		address initiator;
	}

	struct Cancel {
		uint256 senderReceived;
		uint256 recipientReceived;
		uint256 timestamp;
		uint256 responseContentId;
		address initiator;
	}

	struct StreamInfo {
		uint256 streamId;
		uint256 deposit;
		uint256 startTime;
		uint256 stopTime;
		address recipient;
		address sender;
		address tokenAddress;
		Withdrawal[] withdrawals;
		Cancel cancel;
	}

	// ===================
	// ===== Storage =====
	// ===================
	IYlideMailer public ylideMailer;
	ISablier public sablier;
	// contentId => StreamInfo
	mapping(uint256 => StreamInfo) public contentIdToStreamInfo;

	// =====================
	// ===== Constants =====
	// =====================
	uint256 public constant version = 1;

	constructor() Owned() Pausable() {}

	// ===================
	// ===== Setters =====
	// ===================
	function setYlideMailer(address _ylideMailer) external onlyOwner {
		ylideMailer = IYlideMailer(_ylideMailer);
	}

	function setSablier(ISablier _sablier) external onlyOwner {
		sablier = _sablier;
	}

	function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}

	// ===================
	// ===== Getters =====
	// ===================
	function balance(
		uint256 contentId
	) public view returns (uint256 balanceSender, uint256 balanceRecipient) {
		StreamInfo memory streamInfo = contentIdToStreamInfo[contentId];
		return (
			sablier.balanceOf(streamInfo.streamId, address(this)),
			sablier.balanceOf(streamInfo.streamId, streamInfo.recipient)
		);
	}

	function contractType() public pure returns (ContractType) {
		return ContractType.StreamSablier;
	}

	// ============================
	// ===== External Methods =====
	// ============================
	function sendBulkMailWithToken(
		uint256 feedId,
		uint256 uniqueId,
		uint256[] calldata recipients,
		bytes[] calldata keys,
		bytes calldata content,
		StreamArgs[] calldata streamArgs
	) external whenNotPaused returns (uint256) {
		uint256 contentId = ylideMailer.sendBulkMail(
			msg.sender,
			feedId,
			uniqueId,
			recipients,
			keys,
			content
		);
		_handleTokenAttachment(streamArgs, contentId);
		return contentId;
	}

	function addMailRecipientsWithToken(
		uint256 feedId,
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint16 partsCount,
		uint16 blockCountLock,
		uint256[] calldata recipients,
		bytes[] calldata keys,
		StreamArgs[] calldata streamArgs
	) external whenNotPaused returns (uint256) {
		uint256 contentId = ylideMailer.addMailRecipients(
			msg.sender,
			feedId,
			uniqueId,
			firstBlockNumber,
			partsCount,
			blockCountLock,
			recipients,
			keys
		);
		_handleTokenAttachment(streamArgs, contentId);
		return contentId;
	}

	function withdrawFromStream(
		uint256 contentId,
		uint256 amount
	) external whenNotPaused returns (bool) {
		StreamInfo storage streamInfo = contentIdToStreamInfo[contentId];
		if (msg.sender != streamInfo.sender && msg.sender != streamInfo.recipient) {
			revert("caller is not the sender or the recipient of the stream");
		}
		bool success = sablier.withdrawFromStream(streamInfo.streamId, amount);
		if (success) {
			streamInfo.withdrawals.push(
				Withdrawal({amount: amount, timestamp: block.timestamp, initiator: msg.sender})
			);
		}
		return success;
	}

	function cancelStream(uint256 contentId) external whenNotPaused returns (bool) {
		StreamCancelArgs memory streamCancelArgs = _cancelStream(contentId);
		if (streamCancelArgs.success) {
			contentIdToStreamInfo[contentId].cancel = Cancel({
				initiator: msg.sender,
				timestamp: block.timestamp,
				senderReceived: streamCancelArgs.senderReceived,
				recipientReceived: streamCancelArgs.recipientReceived,
				responseContentId: 0
			});
		}
		return streamCancelArgs.success;
	}

	function cancelStreamAndSendBulkMail(
		uint256 feedId,
		uint256 uniqueId,
		uint256[] calldata recipients,
		bytes[] calldata keys,
		bytes calldata content,
		uint256 parentContentId
	) external whenNotPaused returns (uint256) {
		StreamCancelArgs memory streamCancelArgs = _cancelStream(parentContentId);
		if (!streamCancelArgs.success) {
			revert("Stream cannot be cancelled");
		}
		uint256 responseContentId = ylideMailer.sendBulkMail(
			msg.sender,
			feedId,
			uniqueId,
			recipients,
			keys,
			content
		);
		contentIdToStreamInfo[parentContentId].cancel = Cancel({
			initiator: msg.sender,
			timestamp: block.timestamp,
			senderReceived: streamCancelArgs.senderReceived,
			recipientReceived: streamCancelArgs.recipientReceived,
			responseContentId: responseContentId
		});
		return responseContentId;
	}

	function cancelStreamAndAddMailRecipients(
		uint256 feedId,
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint16 partsCount,
		uint16 blockCountLock,
		uint256[] calldata recipients,
		bytes[] calldata keys,
		uint256 parentContentId
	) external whenNotPaused returns (uint256) {
		StreamCancelArgs memory streamCancelArgs = _cancelStream(parentContentId);
		if (!streamCancelArgs.success) {
			revert("Stream cannot be cancelled");
		}
		uint256 responseContentId = ylideMailer.addMailRecipients(
			msg.sender,
			feedId,
			uniqueId,
			firstBlockNumber,
			partsCount,
			blockCountLock,
			recipients,
			keys
		);
		contentIdToStreamInfo[parentContentId].cancel = Cancel({
			initiator: msg.sender,
			timestamp: block.timestamp,
			senderReceived: streamCancelArgs.senderReceived,
			recipientReceived: streamCancelArgs.recipientReceived,
			responseContentId: responseContentId
		});
		return responseContentId;
	}

	// ===========================
	// ===== Private methods =====
	// ===========================
	function _cancelStream(
		uint256 contentId
	) internal returns (StreamCancelArgs memory streamCancelArgs) {
		StreamInfo storage streamInfo = contentIdToStreamInfo[contentId];
		if (msg.sender != streamInfo.sender && msg.sender != streamInfo.recipient) {
			revert("caller is not the sender or the recipient of the stream");
		}
		streamCancelArgs.senderReceived = sablier.balanceOf(streamInfo.streamId, address(this));
		streamCancelArgs.recipientReceived = sablier.balanceOf(
			streamInfo.streamId,
			streamInfo.recipient
		);
		streamCancelArgs.success = sablier.cancelStream(streamInfo.streamId);
		if (streamCancelArgs.success && streamCancelArgs.senderReceived > 0) {
			IERC20(streamInfo.tokenAddress).safeTransfer(
				streamInfo.sender,
				streamCancelArgs.senderReceived
			);
		}
	}

	function _handleTokenAttachment(StreamArgs[] calldata streamArgs, uint256 contentId) internal {
		if (contentIdToStreamInfo[contentId].streamId != 0) {
			revert("YlideStreamSablierV1: contentId already has a stream");
		}
		for (uint256 i; i < streamArgs.length; ) {
			if (streamArgs[i].recipient != address(0)) {
				_createStream(streamArgs[i], contentId);
			}
			unchecked {
				i++;
			}
		}
	}

	function _createStream(StreamArgs calldata streamArgs, uint256 contentId) internal {
		if (address(sablier) == address(0)) {
			revert("YlideStreamSablierV1: sablier not set");
		}
		IERC20(streamArgs.tokenAddress).safeTransferFrom(
			msg.sender,
			address(this),
			streamArgs.deposit
		);
		IERC20(streamArgs.tokenAddress).safeApprove(address(sablier), streamArgs.deposit);

		uint256 streamId = sablier.createStream(
			streamArgs.recipient,
			streamArgs.deposit,
			streamArgs.tokenAddress,
			streamArgs.startTime,
			streamArgs.stopTime
		);

		StreamInfo storage streamInfo = contentIdToStreamInfo[contentId];
		streamInfo.deposit = streamArgs.deposit;
		streamInfo.startTime = streamArgs.startTime;
		streamInfo.stopTime = streamArgs.stopTime;
		streamInfo.recipient = streamArgs.recipient;
		streamInfo.sender = msg.sender;
		streamInfo.tokenAddress = streamArgs.tokenAddress;
		streamInfo.streamId = streamId;
	}
}
