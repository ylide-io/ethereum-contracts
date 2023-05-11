// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct RegistryEntry {
	uint256 previousEventsIndex;
	uint256 publicKey;
	uint64 block;
	uint64 timestamp;
	uint32 keyVersion;
	uint32 registrar;
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
	address payable beneficiary;
}
