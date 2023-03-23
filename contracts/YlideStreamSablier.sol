// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Owned} from "./helpers/Owned.sol";

import {IYlideMailer} from "./interfaces/IYlideMailer.sol";
import {ISablier} from "./interfaces/ISablier.sol";

contract YlideStreamSablier is Owned, Pausable {
	using SafeERC20 for IERC20;

	struct StreamInfo {
		address recipient;
		uint256 deposit;
		address tokenAddress;
		uint256 startTime;
		uint256 stopTime;
	}

	event TokenAttachment(
		uint256 indexed contentId,
		uint256 indexed streamId,
		uint256 deposit,
		uint256 startTime,
		uint256 stopTime,
		address indexed recipient,
		address tokenAddress
	);

	uint256 public constant version = 1;

	IYlideMailer public ylideMailer;

	ISablier public sablier;

	// streamId => sender
	mapping(uint256 => address) streamIdToSender;

	constructor() {}

	function setYlideMailer(IYlideMailer _ylideMailer) external onlyOwner {
		ylideMailer = _ylideMailer;
	}

	function setSablier(ISablier _sablier) external onlyOwner {
		sablier = _sablier;
	}

	function _stream(StreamInfo calldata streamInfo, uint256 contentId) internal {
		IERC20(streamInfo.tokenAddress).safeApprove(address(sablier), streamInfo.deposit);

		uint256 streamId = sablier.createStream(
			streamInfo.recipient,
			streamInfo.deposit,
			streamInfo.tokenAddress,
			streamInfo.startTime,
			streamInfo.stopTime
		);

		streamIdToSender[streamId] = msg.sender;

		emit TokenAttachment(
			contentId,
			streamId,
			streamInfo.deposit,
			streamInfo.startTime,
			streamInfo.stopTime,
			streamInfo.recipient,
			streamInfo.tokenAddress
		);
	}

	function _handleTokenAttachment(StreamInfo[] calldata streamInfos, uint256 contentId) internal {
		for (uint256 i; i < streamInfos.length; ) {
			if (streamInfos[i].recipient != address(0)) {
				_stream(streamInfos[i], contentId);
			}
			unchecked {
				i++;
			}
		}
	}

	function sendBulkMailWithToken(
		uint256 feedId,
		uint256 uniqueId,
		uint256[] calldata recipients,
		bytes[] calldata keys,
		bytes calldata content,
		StreamInfo[] calldata streamInfos
	) public whenNotPaused returns (uint256) {
		uint256 contentId = ylideMailer.sendBulkMail(
			msg.sender,
			feedId,
			uniqueId,
			recipients,
			keys,
			content
		);
		_handleTokenAttachment(streamInfos, contentId);
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
		StreamInfo[] calldata streamInfos
	) public whenNotPaused returns (uint256) {
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
		_handleTokenAttachment(streamInfos, contentId);
		return contentId;
	}

	/**
	 * @notice Withdraws from the contract to the recipient's account.
	 * @dev Throws if the id does not point to a valid stream.
	 *  Throws if the caller is not the sender or the recipient of the stream.
	 *  Throws if the amount exceeds the available balance.
	 *  Throws if there is a token transfer failure.
	 * @param streamId The id of the stream to withdraw tokens from.
	 * @param amount The amount of tokens to withdraw.
	 */
	function withdrawFromStream(uint256 streamId, uint256 amount) external returns (bool) {
		address sender = streamIdToSender[streamId];
		(, address recipient, , , , , , ) = sablier.getStream(streamId);
		if (msg.sender != sender || msg.sender != recipient) {
			revert("caller is not the sender or the recipient of the stream");
		}
		return sablier.withdrawFromStream(streamId, amount);
	}

	/**
	 * @notice Cancels the stream and transfers the tokens back on a pro rata basis.
	 * @dev Throws if the id does not point to a valid stream.
	 *  Throws if the caller is not the sender or the recipient of the stream.
	 *  Throws if there is a token transfer failure.
	 * @param streamId The id of the stream to cancel.
	 * @return bool true=success, otherwise false.
	 */
	function cancelStream(uint256 streamId) external whenNotPaused returns (bool) {
		address sender = streamIdToSender[streamId];
		(, address recipient, , address tokenAddress, , , , ) = sablier.getStream(streamId);
		if (msg.sender != sender || msg.sender != recipient) {
			revert("caller is not the sender or the recipient of the stream");
		}
		uint256 balance = sablier.balanceOf(streamId, address(this));
		bool result = sablier.cancelStream(streamId);
		if (result == true && balance > 0) {
			IERC20(tokenAddress).safeTransfer(sender, balance);
		}
		return result;
	}

	function balanceOf(uint256 streamId, address who) public view returns (uint256 balance) {
		return sablier.balanceOf(streamId, who);
	}

	function getStream(
		uint256 streamId
	)
		external
		view
		returns (
			address sender,
			address recipient,
			uint256 deposit,
			address tokenAddress,
			uint256 startTime,
			uint256 stopTime,
			uint256 remainingBalance,
			uint256 ratePerSecond
		)
	{
		(
			,
			recipient,
			deposit,
			tokenAddress,
			startTime,
			stopTime,
			remainingBalance,
			ratePerSecond
		) = sablier.getStream(streamId);
		sender = streamIdToSender[streamId];
	}

	function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}
}
