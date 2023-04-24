// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Owned} from "./helpers/Owned.sol";
import {CONTRACT_TYPE_SAFE} from "./helpers/Constants.sol";

import {IYlideMailer} from "./interfaces/IYlideMailer.sol";

contract YlideSafeV1 is Owned, Pausable {
	uint256 public constant version = 1;

	IYlideMailer public ylideMailer;

	struct SafeArgs {
		address safeSender;
		address[] safeRecipients;
	}

	error InvalidSender();
	error InvalidArguments();

	event YlideMailerChanged(address indexed ylideMailer);
	event SafeMails(
		uint256 indexed contentId,
		address indexed safeSender,
		address[] safeRecipients
	);

	constructor(IYlideMailer _ylideMailer) Owned() Pausable() {
		ylideMailer = _ylideMailer;
	}

	function setYlideMailer(IYlideMailer _ylideMailer) external onlyOwner {
		ylideMailer = _ylideMailer;
		emit YlideMailerChanged(address(_ylideMailer));
	}

	function sendBulkMail(
		IYlideMailer.SendBulkArgs calldata args,
		IYlideMailer.SignatureArgs calldata signatureArgs,
		SafeArgs calldata safeArgs
	) external payable whenNotPaused returns (uint256) {
		_validate(args.recipients, signatureArgs.sender, safeArgs);

		uint256 contentId = ylideMailer.sendBulkMail{value: msg.value}(
			args,
			signatureArgs,
			IYlideMailer.Supplement(address(this), CONTRACT_TYPE_SAFE)
		);

		emit SafeMails(contentId, safeArgs.safeSender, safeArgs.safeRecipients);

		return contentId;
	}

	function addMailRecipients(
		IYlideMailer.AddMailRecipientsArgs calldata args,
		IYlideMailer.SignatureArgs calldata signatureArgs,
		SafeArgs calldata safeArgs
	) external payable whenNotPaused returns (uint256) {
		_validate(args.recipients, signatureArgs.sender, safeArgs);

		uint256 contentId = ylideMailer.addMailRecipients{value: msg.value}(
			args,
			signatureArgs,
			IYlideMailer.Supplement(address(this), CONTRACT_TYPE_SAFE)
		);

		emit SafeMails(contentId, safeArgs.safeSender, safeArgs.safeRecipients);

		return contentId;
	}

	function _validate(
		uint256[] calldata recipients,
		address sender,
		SafeArgs calldata safeArgs
	) internal view {
		if (sender != msg.sender) revert InvalidSender();
		if (recipients.length != safeArgs.safeRecipients.length) revert InvalidArguments();
	}

	function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}
}
