// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Owned} from "./helpers/Owned.sol";
import {CONTRACT_TYPE_SAFE} from "./helpers/Constants.sol";

import {IYlideMailer} from "./interfaces/IYlideMailer.sol";
import {ISafe} from "./interfaces/ISafe.sol";

// TODO: ensure that ISafe safe contract is really from Gnosis Safe
contract YlideSafeV1 is Owned, Pausable {
	uint256 public constant version = 1;

	IYlideMailer public ylideMailer;

	mapping(bytes32 => SafeContract) public safeVersionToSafeContract;

	error InvalidSender();
	error NotSafeOwner();
	error InvalidString();
	error InvalidAddress();
	error InvalidSingleton();
	error InvalidCodehash();

	event YlideMailerChanged(address indexed ylideMailer);
	event SafeVersionToSafeContractSet(
		string indexed version,
		address indexed singleton,
		bytes32 indexed codehash
	);
	event SentBulkMail(address indexed sender, address indexed safe, uint256 indexed contentId);
	event SentAddMailRecipients(
		address indexed sender,
		address indexed safe,
		uint256 indexed contentId
	);

	struct SafeContract {
		address singleton;
		bytes32 codehash;
	}

	constructor(IYlideMailer _ylideMailer) Owned() Pausable() {
		ylideMailer = _ylideMailer;
	}

	function setYlideMailer(IYlideMailer _ylideMailer) external onlyOwner {
		ylideMailer = _ylideMailer;
		emit YlideMailerChanged(address(_ylideMailer));
	}

	function setSafeVersionToSafeContract(
		string calldata _version,
		SafeContract calldata safeContract
	) external onlyOwner {
		safeVersionToSafeContract[stringToBytes(_version)] = safeContract;
		emit SafeVersionToSafeContractSet(_version, safeContract.singleton, safeContract.codehash);
	}

	function sendBulkMail(
		IYlideMailer.SendBulkArgs calldata args,
		IYlideMailer.SignatureArgs memory signatureArgs,
		ISafe safe
	) external payable whenNotPaused returns (uint256) {
		if (signatureArgs.sender != msg.sender) revert InvalidSender();
		validateSafe(safe, msg.sender);

		uint256 contentId = ylideMailer.sendBulkMail{value: msg.value}(
			args,
			signatureArgs,
			IYlideMailer.Supplement(address(safe), CONTRACT_TYPE_SAFE)
		);
		emit SentBulkMail(msg.sender, address(safe), contentId);
		return contentId;
	}

	function addMailRecipients(
		IYlideMailer.AddMailRecipientsArgs calldata args,
		IYlideMailer.SignatureArgs memory signatureArgs,
		ISafe safe
	) external payable whenNotPaused returns (uint256) {
		if (signatureArgs.sender != msg.sender) revert InvalidSender();
		validateSafe(safe, msg.sender);

		uint256 contentId = ylideMailer.addMailRecipients{value: msg.value}(
			args,
			signatureArgs,
			IYlideMailer.Supplement(address(safe), CONTRACT_TYPE_SAFE)
		);
		emit SentAddMailRecipients(msg.sender, address(safe), contentId);
		return contentId;
	}

	function validateSafe(ISafe safe, address user) public view {
		if (safe.isOwner(user) == false) revert NotSafeOwner();
		(bytes32 _version, address singleton) = getSafeInfo(safe);
		SafeContract memory safeContract = safeVersionToSafeContract[_version];
		if (safeContract.singleton != singleton) revert InvalidSingleton();
		if (safeContract.codehash != address(safe).codehash) revert InvalidCodehash();
	}

	function getSafeInfo(ISafe safe) public view returns (bytes32, address) {
		string memory _version = safe.VERSION();
		bytes memory safeSingleton = safe.getStorageAt(0, 1);
		return (stringToBytes(_version), bytesToAddress(safeSingleton));
	}

	function stringToBytes(string memory v) public pure returns (bytes32 result) {
		if (bytes(v).length == 0) return 0x0;
		if (bytes(v).length > 32) revert InvalidString();

		assembly {
			result := mload(add(v, 32))
		}
	}

	function bytesToAddress(bytes memory data) public pure returns (address) {
		if (data.length != 20) revert InvalidAddress();
		return address(uint160(bytes20(bytes(data))));
	}

	function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}
}
