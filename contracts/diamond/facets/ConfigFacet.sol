// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {YlideStorage} from "../storage/YlideStorage.sol";
import {MailingFeed, BroadcastFeed, RegistryEntry} from "../storage/DiamondStorage.sol";
import {LibOwner} from "../libraries/LibOwner.sol";
import {IERC173} from "../interfaces/IERC173.sol";

// Contains all getters for YlideStorage variables
// and simple setters for all of them
// including ownership of YlideDiamond
contract ConfigFacet is YlideStorage, IERC173 {
	// ================================
	// =========== Errors =============
	// ================================

	error NotFeedOwner();

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

	function mailingFeeds(uint256 feedId) external view returns (MailingFeed memory) {
		return s.mailingFeeds[feedId];
	}

	function broadcastFeeds(uint256 feedId) external view returns (BroadcastFeed memory) {
		return s.broadcastFeeds[feedId];
	}

	function bouncers(address bouncer) external view returns (bool) {
		return s.bouncers[bouncer];
	}

	function newcomerBonus() external view returns (uint256) {
		return s.newcomerBonus;
	}

	function referrerBonus() external view returns (uint256) {
		return s.referrerBonus;
	}

	function contentPartFee() external view returns (uint256) {
		return s.contentPartFee;
	}

	function recipientFee() external view returns (uint256) {
		return s.recipientFee;
	}

	function broadcastFee() external view returns (uint256) {
		return s.broadcastFee;
	}

	function broadcastFeedCreationPrice() external view returns (uint256) {
		return s.broadcastFeedCreationPrice;
	}

	function mailingFeedCreationPrice() external view returns (uint256) {
		return s.mailingFeedCreationPrice;
	}

	function beneficiary() external view returns (address payable) {
		return s.beneficiary;
	}

	function broadcastIdToWriters(uint256 feedId, address writer) external view returns (bool) {
		return s.broadcastIdToWriters[feedId][writer];
	}

	function feedIdToRecipientToMailIndex(
		uint256 feedId,
		uint256 recipient
	) external view returns (uint256) {
		return s.feedIdToRecipientToMailIndex[feedId][recipient];
	}

	function feedIdToRecipientMessagesCount(
		uint256 feedId,
		uint256 recipient
	) external view returns (uint256) {
		return s.feedIdToRecipientMessagesCount[feedId][recipient];
	}

	function recipientToMailingFeedJoinEventsIndex(
		uint256 recipient
	) external view returns (uint256) {
		return s.recipientToMailingFeedJoinEventsIndex[recipient];
	}

	function addressToPublicKey(address addr) external view returns (RegistryEntry memory) {
		return s.addressToPublicKey[addr];
	}

	function owner() external view override returns (address owner_) {
		owner_ = s.contractOwner;
	}

	// ================================
	// =========== Setters ============
	// ================================

	function setFees(
		uint256 _contentPartFee,
		uint256 _recipientFee,
		uint256 _broadcastFee
	) external {
		LibOwner.enforceIsContractOwner(s);
		s.contentPartFee = _contentPartFee;
		s.recipientFee = _recipientFee;
		s.broadcastFee = _broadcastFee;
	}

	function setPrices(
		uint256 _broadcastFeedCreationPrice,
		uint256 _mailingFeedCreationPrice
	) external {
		LibOwner.enforceIsContractOwner(s);
		s.broadcastFeedCreationPrice = _broadcastFeedCreationPrice;
		s.mailingFeedCreationPrice = _mailingFeedCreationPrice;
	}

	function setBeneficiary(address payable _beneficiary) external {
		LibOwner.enforceIsContractOwner(s);
		s.beneficiary = _beneficiary;
	}

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

	function transferOwnership(address _newOwner) external override {
		LibOwner.enforceIsContractOwner(s);
		address previousOwner = s.contractOwner;
		s.contractOwner = _newOwner;
		emit OwnershipTransferred(previousOwner, _newOwner);
	}
}
