// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Owned} from "./helpers/Owned.sol";
import {CONTRACT_TYPE_SAFE} from "./helpers/Constants.sol";

import {IYlideMailer} from "./interfaces/IYlideMailer.sol";
import {ISafe} from "./interfaces/ISafe.sol";

contract YlideSafeV1 is Owned, Pausable {
	uint256 public constant version = 1;

	IYlideMailer public ylideMailer;

	error InvalidSender();
	error NotSafeOwner();

	event YlideMailerChanged(address indexed ylideMailer);

	constructor(IYlideMailer _ylideMailer) Owned() Pausable() {
		ylideMailer = _ylideMailer;
	}

	function setYlideMailer(IYlideMailer _ylideMailer) external onlyOwner {
		ylideMailer = _ylideMailer;
		emit YlideMailerChanged(address(_ylideMailer));
	}

	function sendBulkMail(
		IYlideMailer.SendBulkArgs calldata args,
		IYlideMailer.SignatureArgs memory signatureArgs,
		ISafe safe
	) external payable whenNotPaused returns (uint256) {
		if (signatureArgs.sender != msg.sender) revert InvalidSender();
		if (safe.isOwner(msg.sender) == false) revert NotSafeOwner();

		return
			ylideMailer.sendBulkMail{value: msg.value}(
				args,
				signatureArgs,
				IYlideMailer.Supplement(address(safe), CONTRACT_TYPE_SAFE)
			);
	}

	function addMailRecipients(
		IYlideMailer.AddMailRecipientsArgs calldata args,
		IYlideMailer.SignatureArgs memory signatureArgs,
		ISafe safe
	) external payable whenNotPaused returns (uint256) {
		if (signatureArgs.sender != msg.sender) revert InvalidSender();
		if (safe.isOwner(msg.sender) == false) revert NotSafeOwner();

		return
			ylideMailer.addMailRecipients{value: msg.value}(
				args,
				signatureArgs,
				IYlideMailer.Supplement(address(safe), CONTRACT_TYPE_SAFE)
			);
	}

	function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}
}
