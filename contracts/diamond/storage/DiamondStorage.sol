// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {LibListMap} from "../libraries/LibListMap.sol";

struct RegistryEntry {
	uint256 previousEventsIndex;
	uint256 publicKey;
	uint64 block;
	uint64 timestamp;
	uint32 keyVersion;
	// TODO: change to uint32 and ownership management or NFT holder
	address registrar;
	// uint32 registrar;
}

struct BroadcastFeed {
	address owner;
	address payable beneficiary;
	uint256 broadcastFee;
	bool isPublic;
	uint256 messagesIndex;
	uint256 messagesCount;
}

struct MailingFeed {
	address owner;
	address payable beneficiary;
	uint256 recipientFee;
}

struct TokenInfo {
	uint256 amount;
	address token;
	address sender;
	bool withdrawn;
	uint256 stakeBlockedUntil;
	uint256 ylideCommission;
	uint256 registrarCommission;
}

struct FacetAddressAndPosition {
	address facetAddress;
	uint96 functionSelectorPosition; // position in facetFunctionSelectors.functionSelectors array
}

struct FacetFunctionSelectors {
	bytes4[] functionSelectors;
	uint256 facetAddressPosition; // position of facetAddress in facetAddresses array
}

struct DiamondStorage {
	//
	// ================================
	// ======= Diamond specific =======
	// ================================
	//
	// maps function selector to the facet address and
	// the position of the selector in the facetFunctionSelectors.selectors array
	mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;
	// maps facet addresses to function selectors
	mapping(address => FacetFunctionSelectors) facetFunctionSelectors;
	// facet addresses
	address[] facetAddresses;
	// Used to query if a contract implements an interface.
	// Used to implement ERC-165.
	mapping(bytes4 => bool) supportedInterfaces;
	// owner of the contract
	address contractOwner;
	//
	// ================================
	// ======= Ylide specific =======
	// ================================
	//
	mapping(address => RegistryEntry) addressToPublicKey;
	mapping(address => bool) bouncers;
	mapping(uint256 => MailingFeed) mailingFeeds;
	mapping(uint256 => mapping(uint256 => uint256)) feedIdToRecipientToMailIndex;
	mapping(uint256 => mapping(uint256 => uint256)) feedIdToRecipientMessagesCount;
	mapping(uint256 => BroadcastFeed) broadcastFeeds;
	mapping(uint256 => mapping(address => bool)) broadcastIdToWriters;
	mapping(uint256 => uint256) recipientToMailingFeedJoinEventsIndex;
	uint256 newcomerBonus;
	uint256 referrerBonus;
	uint256 contentPartFee;
	uint256 recipientFee;
	uint256 broadcastFee;
	uint256 broadcastFeedCreationPrice;
	uint256 mailingFeedCreationPrice;
	address payable ylideBeneficiary;
	// Pay for attention specific
	// tracking funds of beneficiaries of pay for attention (receiver interface, user referrer etc)
	// TODO: rewrite to registrar
	mapping(address => mapping(address => uint256)) addressToTokenToAmount;
	// globally allowed tokens by ylide
	LibListMap._address allowedTokens;
	mapping(address => uint256) defaultPaywallTokenToAmount;
	// user specific settings for pay for attention
	mapping(uint256 => mapping(address => uint256)) recipientToPaywallTokenToAmount;
	mapping(uint256 => mapping(address => bool)) recipientToWhitelistedSender;
	// info on staked tokens
	mapping(uint256 => mapping(uint256 => TokenInfo)) contentIdToRecipientToTokenInfo;
	// config of staking
	uint256 stakeLockUpPeriod;
	// Percentages denominated in 1e2. 100% = 10000 wei || 0.27% = 27 wei
	uint256 ylideCommissionPercentage;
	mapping(address => uint256) registrarToCommissionPercentage;
}
