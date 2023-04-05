// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {Owned} from "./helpers/Owned.sol";

import {IYlideMailer} from "./interfaces/IYlideMailer.sol";
import {IYlideTokenAttachment} from "./interfaces/IYlideTokenAttachment.sol";

contract YlidePayV1 is IYlideTokenAttachment, Owned, Pausable {
	using SafeERC20 for IERC20;

	struct TransferInfo {
		uint256 amountOrTokenId;
		address recipient;
		address token;
		TokenType tokenType;
	}

	enum TokenType {
		ERC20,
		ERC721
	}

	event TokenAttachment(
		uint256 indexed contentId,
		uint256 amountOrTokenId,
		address indexed recipient,
		address indexed sender,
		address token,
		TokenType tokenType
	);

	error InvalidSender();

	uint256 public constant version = 1;

	IYlideMailer public ylideMailer;

	constructor(IYlideMailer _ylideMailer) Owned() Pausable() {
		ylideMailer = _ylideMailer;
	}

	function contractType() public pure returns (ContractType) {
		return ContractType.Pay;
	}

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
		IYlideMailer.SendBulkArgs calldata args,
		IYlideMailer.SignatureArgs memory signatureArgs,
		TransferInfo[] calldata transferInfos
	) external payable whenNotPaused returns (uint256) {
		if (signatureArgs.sender != msg.sender) revert InvalidSender();
		uint256 contentId = ylideMailer.sendBulkMail{value: msg.value}(args, signatureArgs);
		_handleTokenAttachment(transferInfos, contentId);
		return contentId;
	}

	function addMailRecipientsWithToken(
		IYlideMailer.AddMailRecipientsArgs calldata args,
		IYlideMailer.SignatureArgs memory signatureArgs,
		TransferInfo[] calldata transferInfos
	) external payable whenNotPaused returns (uint256) {
		if (signatureArgs.sender != msg.sender) revert InvalidSender();
		uint256 contentId = ylideMailer.addMailRecipients{value: msg.value}(args, signatureArgs);
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
