// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {YlideStorage} from "../storage/YlideStorage.sol";
import {MailingFeed, BroadcastFeed} from "../storage/DiamondStorage.sol";

import {LibOwner} from "../libraries/LibOwner.sol";

contract ConfigFacet is YlideStorage {
	// ================================
	// =========== Errors =============
	// ================================

	error NotFeedOwner();
	error FeedAlreadyExists();
	error FeedExists();

	// ================================
	// ===== Internal methods =========
	// ================================

	function validateFeedOwner(uint256 feedId) internal view {
		if (msg.sender != s.mailingFeeds[feedId].owner) {
			revert NotFeedOwner();
		}
	}

	function validateBroadCastFeedOwner(uint256 feedId) internal view {
		if (msg.sender != s.broadcastFeeds[feedId].owner) {
			revert NotFeedOwner();
		}
	}

	// ================================
	// ===== External methods =========
	// ================================

	// ================================
	// =========== Getters ============
	// ================================
	function getMailingFeedRecipientIndex(
		uint256 feedId,
		uint256 recipient
	) external view returns (uint256) {
		return s.feedIdToRecipientToMailIndex[feedId][recipient];
	}

	function getMailingFeedRecipientMessagesCount(
		uint256 feedId,
		uint256 recipient
	) external view returns (uint256) {
		return s.feedIdToRecipientMessagesCount[feedId][recipient];
	}

	function getMailingFeed(uint256 feedId) external view returns (MailingFeed memory) {
		return s.mailingFeeds[feedId];
	}

	function getBroadcastFeed(uint256 feedId) external view returns (BroadcastFeed memory) {
		return s.broadcastFeeds[feedId];
	}

	function getRecipientToMailingFeedJoinEventsIndex(
		uint256 recipient
	) external view returns (uint256) {
		return s.recipientToMailingFeedJoinEventsIndex[recipient];
	}

	// ================================
	// =========== Setters ============
	// ================================

	function setBouncer(address newBouncer, bool val) external {
		LibOwner.enforceIsContractOwner(s);
		if (newBouncer != address(0)) {
			s.bouncers[newBouncer] = val;
		}
	}

	function setBonuses(uint256 _newcomerBonus, uint256 _referrerBonus) external {
		LibOwner.enforceIsContractOwner(s);
		s.newcomerBonus = _newcomerBonus;
		s.referrerBonus = _referrerBonus;
	}

	function setMailingFeedFees(uint256 feedId, uint256 _recipientFee) external {
		validateFeedOwner(feedId);
		s.mailingFeeds[feedId].recipientFee = _recipientFee;
	}

	function setBroadcastFeedFees(uint256 feedId, uint256 _broadcastFee) external {
		validateBroadCastFeedOwner(feedId);
		s.broadcastFeeds[feedId].broadcastFee = _broadcastFee;
	}

	function transferMailingFeedOwnership(uint256 feedId, address newOwner) external {
		validateFeedOwner(feedId);
		s.mailingFeeds[feedId].owner = newOwner;
		emit MailingFeedOwnershipTransferred(feedId, newOwner);
	}

	function setMailingFeedBeneficiary(uint256 feedId, address payable newBeneficiary) external {
		validateFeedOwner(feedId);
		s.mailingFeeds[feedId].beneficiary = newBeneficiary;
		emit MailingFeedBeneficiaryChanged(feedId, newBeneficiary);
	}

	function changeBroadcastFeedPublicity(uint256 feedId, bool isPublic) external {
		validateBroadCastFeedOwner(feedId);
		s.broadcastFeeds[feedId].isPublic = isPublic;
		emit BroadcastFeedPublicityChanged(feedId, isPublic);
	}

	function addBroadcastFeedWriter(uint256 feedId, address writer) external {
		validateBroadCastFeedOwner(feedId);
		s.broadcastIdToWriters[feedId][writer] = true;
		emit BroadcastFeedWriterChange(feedId, writer, true);
	}

	function removeBroadcastFeedWriter(uint256 feedId, address writer) external {
		validateBroadCastFeedOwner(feedId);
		delete s.broadcastIdToWriters[feedId][writer];
		emit BroadcastFeedWriterChange(feedId, writer, false);
	}

	function transferBroadcastFeedOwnership(uint256 feedId, address newOwner) external {
		validateBroadCastFeedOwner(feedId);
		s.broadcastFeeds[feedId].owner = newOwner;
		emit BroadcastFeedOwnershipTransferred(feedId, newOwner);
	}

	function setBroadcastFeedBeneficiary(uint256 feedId, address payable newBeneficiary) external {
		validateBroadCastFeedOwner(feedId);
		s.broadcastFeeds[feedId].beneficiary = newBeneficiary;
		emit BroadcastFeedBeneficiaryChanged(feedId, newBeneficiary);
	}

	function createMailingFeed(uint256 uniqueId) external payable returns (uint256) {
		uint256 feedId = uint256(keccak256(abi.encodePacked(msg.sender, uint256(0), uniqueId)));

		if (s.mailingFeeds[feedId].owner != address(0)) {
			revert FeedAlreadyExists();
		}

		s.mailingFeeds[feedId].owner = msg.sender;
		s.mailingFeeds[feedId].beneficiary = payable(msg.sender);

		if (s.mailingFeedCreationPrice > 0) {
			s.beneficiary.transfer(s.mailingFeedCreationPrice);
		}

		emit MailingFeedCreated(feedId, msg.sender);

		return feedId;
	}

	function createBroadcastFeed(
		uint256 uniqueId,
		bool isPublic
	) external payable returns (uint256) {
		uint256 feedId = uint256(keccak256(abi.encodePacked(msg.sender, uint256(0), uniqueId)));

		if (s.broadcastFeeds[feedId].owner != address(0)) {
			revert FeedExists();
		}

		s.broadcastFeeds[feedId].owner = msg.sender;
		s.broadcastFeeds[feedId].beneficiary = payable(msg.sender);
		s.broadcastFeeds[feedId].isPublic = isPublic;
		s.broadcastIdToWriters[feedId][msg.sender] = true;
		s.broadcastFeeds[feedId].messagesIndex = 0;
		s.broadcastFeeds[feedId].messagesCount = 0;

		if (s.broadcastFeedCreationPrice > 0) {
			s.beneficiary.transfer(s.broadcastFeedCreationPrice);
		}

		emit BroadcastFeedCreated(feedId, msg.sender);

		return feedId;
	}
}
