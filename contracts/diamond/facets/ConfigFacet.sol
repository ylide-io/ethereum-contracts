// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {YlideStorage, MailingFeed, BroadcastFeed, RegistryEntry, StakeInfo} from "../YlideStorage.sol";
import {Owner} from "../libraries/Owner.sol";
import {ListMap} from "../libraries/ListMap.sol";
import {IERC173} from "../interfaces/IERC173.sol";

// Contains all getters for YlideStorage variables
// and simple setters for all of them
// including ownership of YlideDiamond
contract ConfigFacet is YlideStorage, IERC173 {
	// ================================
	// ====== Arguments structs =======
	// ================================
	struct PayWallArgs {
		address token;
		uint256 amount;
	}

	struct WhitelistArgs {
		address sender;
		bool status;
	}
	// ================================
	// =========== Errors =============
	// ================================

	error NotFeedOwner();

	// ================================
	// ===== Internal methods =========
	// ================================

	function _validateFeedOwner(uint256 feedId) internal view {
		if (msg.sender != s.mailingFeeds[feedId].owner) {
			revert NotFeedOwner();
		}
	}

	function _validateBroadCastFeedOwner(uint256 feedId) internal view {
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

	function ylideBeneficiary() external view returns (address payable) {
		return s.ylideBeneficiary;
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

	function addressToTokenToAmount(address addr, address token) external view returns (uint256) {
		return s.addressToTokenToAmount[addr][token];
	}

	function recipientToPaywallTokenToAmount(
		uint256 recipient,
		address token
	) external view returns (uint256) {
		return s.recipientToPaywallTokenToAmount[recipient][token];
	}

	function allowedTokens() external view returns (address[] memory) {
		return s.allowedTokens.list;
	}

	function isAllowedToken(address token) external view returns (bool) {
		return s.allowedTokens.includes[token];
	}

	function defaultPaywallTokenToAmount(address token) external view returns (uint256) {
		return s.defaultPaywallTokenToAmount[token];
	}

	function recipientToWhitelistedSender(
		uint256 recipient,
		address sender
	) external view returns (bool) {
		return s.recipientToWhitelistedSender[recipient][sender];
	}

	function userSelfWhitelisted(address user) external view returns (bool) {
		return
			s.recipientToWhitelistedSender[uint160(user)][user] &&
			s.recipientToWhitelistedSender[uint256(sha256(abi.encode(user)))][user];
	}

	function contentIdToRecipientToStakeInfo(
		uint256 contentId,
		uint256 recipient
	) external view returns (StakeInfo memory) {
		return s.contentIdToRecipientToStakeInfo[contentId][recipient];
	}

	function stakeLockUpPeriod() external view returns (uint256) {
		return s.stakeLockUpPeriod;
	}

	function ylideCommissionPercentage() external view returns (uint256) {
		return s.ylideCommissionPercentage;
	}

	function registrarToCommissionPercentage(address referrer) external view returns (uint256) {
		return s.registrarToCommissionPercentage[referrer];
	}

	function getRecipientPaywallInfo(
		uint256 recipient,
		address sender
	) external view returns (PayWallArgs[] memory) {
		address[] memory _allowedTokens = s.allowedTokens.list;
		PayWallArgs[] memory payWallOptions = new PayWallArgs[](_allowedTokens.length);
		for (uint256 i; i < _allowedTokens.length; ) {
			uint256 amount;
			uint256 userAmount = s.recipientToPaywallTokenToAmount[recipient][_allowedTokens[i]];
			if (s.recipientToWhitelistedSender[recipient][sender]) {
				amount = 0;
			} else if (userAmount == 0) {
				amount = s.defaultPaywallTokenToAmount[_allowedTokens[i]];
			} else {
				amount = userAmount;
			}
			uint256 ylideCommission = (s.ylideCommissionPercentage * amount) / 10000;
			uint256 referrerCommission = (s.registrarToCommissionPercentage[
				s.addressToPublicKey[address(uint160(recipient))].registrar
			] * amount) / 10000;
			payWallOptions[i] = PayWallArgs(
				_allowedTokens[i],
				amount + ylideCommission + referrerCommission
			);
			unchecked {
				i++;
			}
		}
		return payWallOptions;
	}

	// ================================
	// =========== Setters ============
	// ================================

	function setFees(
		uint256 _contentPartFee,
		uint256 _recipientFee,
		uint256 _broadcastFee
	) external {
		Owner.enforceIsContractOwner(s);
		s.contentPartFee = _contentPartFee;
		s.recipientFee = _recipientFee;
		s.broadcastFee = _broadcastFee;
	}

	function setPrices(
		uint256 _broadcastFeedCreationPrice,
		uint256 _mailingFeedCreationPrice
	) external {
		Owner.enforceIsContractOwner(s);
		s.broadcastFeedCreationPrice = _broadcastFeedCreationPrice;
		s.mailingFeedCreationPrice = _mailingFeedCreationPrice;
	}

	function setYlideBeneficiary(address payable _ylideBeneficiary) external {
		Owner.enforceIsContractOwner(s);
		s.ylideBeneficiary = _ylideBeneficiary;
	}

	function setBouncer(address newBouncer, bool val) external {
		Owner.enforceIsContractOwner(s);
		if (newBouncer != address(0)) {
			s.bouncers[newBouncer] = val;
		}
	}

	function setBonuses(uint256 _newcomerBonus, uint256 _referrerBonus) external {
		Owner.enforceIsContractOwner(s);
		s.newcomerBonus = _newcomerBonus;
		s.referrerBonus = _referrerBonus;
	}

	function setMailingFeedFees(uint256 feedId, uint256 _recipientFee) external {
		_validateFeedOwner(feedId);
		s.mailingFeeds[feedId].recipientFee = _recipientFee;
	}

	function setBroadcastFeedFees(uint256 feedId, uint256 _broadcastFee) external {
		_validateBroadCastFeedOwner(feedId);
		s.broadcastFeeds[feedId].broadcastFee = _broadcastFee;
	}

	function transferMailingFeedOwnership(uint256 feedId, address newOwner) external {
		_validateFeedOwner(feedId);
		s.mailingFeeds[feedId].owner = newOwner;
		emit MailingFeedOwnershipTransferred(feedId, newOwner);
	}

	function setMailingFeedBeneficiary(uint256 feedId, address payable newBeneficiary) external {
		_validateFeedOwner(feedId);
		s.mailingFeeds[feedId].beneficiary = newBeneficiary;
		emit MailingFeedBeneficiaryChanged(feedId, newBeneficiary);
	}

	function changeBroadcastFeedPublicity(uint256 feedId, bool isPublic) external {
		_validateBroadCastFeedOwner(feedId);
		s.broadcastFeeds[feedId].isPublic = isPublic;
		emit BroadcastFeedPublicityChanged(feedId, isPublic);
	}

	function addBroadcastFeedWriter(uint256 feedId, address writer) external {
		_validateBroadCastFeedOwner(feedId);
		s.broadcastIdToWriters[feedId][writer] = true;
		emit BroadcastFeedWriterChange(feedId, writer, true);
	}

	function removeBroadcastFeedWriter(uint256 feedId, address writer) external {
		_validateBroadCastFeedOwner(feedId);
		delete s.broadcastIdToWriters[feedId][writer];
		emit BroadcastFeedWriterChange(feedId, writer, false);
	}

	function transferBroadcastFeedOwnership(uint256 feedId, address newOwner) external {
		_validateBroadCastFeedOwner(feedId);
		s.broadcastFeeds[feedId].owner = newOwner;
		emit BroadcastFeedOwnershipTransferred(feedId, newOwner);
	}

	function setBroadcastFeedBeneficiary(uint256 feedId, address payable newBeneficiary) external {
		_validateBroadCastFeedOwner(feedId);
		s.broadcastFeeds[feedId].beneficiary = newBeneficiary;
		emit BroadcastFeedBeneficiaryChanged(feedId, newBeneficiary);
	}

	function transferOwnership(address _newOwner) external override {
		Owner.enforceIsContractOwner(s);
		address previousOwner = s.contractOwner;
		s.contractOwner = _newOwner;
		emit OwnershipTransferred(previousOwner, _newOwner);
	}

	function setStakeLockUpPeriod(uint256 _stakeLockUpPeriod) external {
		Owner.enforceIsContractOwner(s);
		s.stakeLockUpPeriod = _stakeLockUpPeriod;
	}

	function setYlideCommissionPercentage(uint256 _ylideCommissionPercentage) external {
		Owner.enforceIsContractOwner(s);
		s.ylideCommissionPercentage = _ylideCommissionPercentage;
	}

	function setRegistrarToCommissionPercentage(uint256 commissionPercentage) external {
		s.registrarToCommissionPercentage[msg.sender] = commissionPercentage;
	}

	function setPaywall(PayWallArgs[] calldata args) external {
		for (uint256 i; i < args.length; ) {
			s.recipientToPaywallTokenToAmount[uint160(msg.sender)][args[i].token] = args[i].amount;
			unchecked {
				i++;
			}
		}
	}

	function whitelistSenders(WhitelistArgs[] calldata args) external {
		for (uint256 i; i < args.length; ) {
			s.recipientToWhitelistedSender[uint160(msg.sender)][args[i].sender] = args[i].status;
			unchecked {
				i++;
			}
		}
	}

	function whitelistOneself() external {
		s.recipientToWhitelistedSender[uint160(msg.sender)][msg.sender] = true;
		s.recipientToWhitelistedSender[uint256(sha256(abi.encode(msg.sender)))][msg.sender] = true;
	}

	function setPaywallDefault(PayWallArgs[] calldata args) external {
		Owner.enforceIsContractOwner(s);
		for (uint256 i; i < args.length; ) {
			s.defaultPaywallTokenToAmount[args[i].token] = args[i].amount;
			unchecked {
				i++;
			}
		}
	}

	function addAllowedTokens(address[] calldata args) external {
		Owner.enforceIsContractOwner(s);
		ListMap.addList(s.allowedTokens, args);
	}

	function removeAllowedTokens(address[] calldata args) external {
		Owner.enforceIsContractOwner(s);
		ListMap.removeList(s.allowedTokens, args);
	}
}
