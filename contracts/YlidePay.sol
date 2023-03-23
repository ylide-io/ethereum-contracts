// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {Owned} from "./helpers/Owned.sol";

import {IYlideMailer} from "./interfaces/IYlideMailer.sol";
import {IYlideTokenAttachment} from "./interfaces/IYlideTokenAttachment.sol";

contract YlidePay is IYlideTokenAttachment, Owned, Pausable {
	using SafeERC20 for IERC20;

	uint256 public constant version = 1;

	IYlideMailer public ylideMailer;

	constructor() {}

	function setYlideMailer(IYlideMailer _ylideMailer) external onlyOwner {
		ylideMailer = _ylideMailer;
	}

	function _safeTransferFrom(TransferInfo calldata transferInfo, uint256 contentId) internal {
		if (transferInfo.tokenType == TokenType.ERC20) {
			IERC20(transferInfo.token).safeTransferFrom(
				msg.sender,
				transferInfo.recipient,
				transferInfo.amountOrTokenId
			);
		} else if (transferInfo.tokenType == TokenType.ERC721) {
			IERC721(transferInfo.token).safeTransferFrom(
				msg.sender,
				transferInfo.recipient,
				transferInfo.amountOrTokenId
			);
		}
		emit TokenAttachment(
			contentId,
			transferInfo.amountOrTokenId,
			transferInfo.recipient,
			msg.sender,
			transferInfo.token,
			transferInfo.tokenType
		);
	}

	function _handleTokenAttachment(
		TransferInfo[] calldata transferInfos,
		uint256 contentId
	) internal {
		for (uint256 i; i < transferInfos.length; ) {
			if (transferInfos[i].recipient != address(0)) {
				_safeTransferFrom(transferInfos[i], contentId);
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
		TransferInfo[] calldata transferInfos
	) public payable whenNotPaused returns (uint256) {
		uint256 contentId = ylideMailer.sendBulkMail(
			msg.sender,
			feedId,
			uniqueId,
			recipients,
			keys,
			content
		);
		_handleTokenAttachment(transferInfos, contentId);
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
		TransferInfo[] calldata transferInfos
	) public payable whenNotPaused returns (uint256) {
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
		_handleTokenAttachment(transferInfos, contentId);
		return contentId;
	}

	function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}
}
