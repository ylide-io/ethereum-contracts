// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ListMap} from "./libraries/ListMap.sol";

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

struct StakeInfoSender {
	uint256 stakeBlockedUntil;
	address token;
	address sender;
	uint16 ylideCommissionPercentage;
	bool canceled;
}

struct StakeInfoRecipient {
	uint160 amount;
	uint16 registrarCommissionPercentage;
	bool claimed;
}

struct FacetAddressAndPosition {
	address facetAddress;
	uint96 functionSelectorPosition; // position in facetFunctionSelectors.functionSelectors array
}

struct FacetFunctionSelectors {
	bytes4[] functionSelectors;
	uint256 facetAddressPosition; // position of facetAddress in facetAddresses array
}

struct Storage {
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
	ListMap._address allowedTokens;
	mapping(address => uint256) defaultPaywallTokenToAmount;
	// user specific settings for pay for attention
	mapping(uint256 => mapping(address => uint256)) recipientToPaywallTokenToAmount;
	mapping(uint256 => mapping(address => bool)) recipientToWhitelistedSender;
	// info on staked tokens
	mapping(uint256 => StakeInfoSender) contentIdToStakeInfoSender;
	mapping(uint256 => mapping(uint160 => StakeInfoRecipient)) contentIdToRecipientToStakeInfo;
	// config of staking
	uint256 stakeLockUpPeriod;
	// Percentages denominated in 1e2. 100% = 10000 wei || 0.27% = 27 wei
	uint16 ylideCommissionPercentage;
	mapping(address => uint16) registrarToCommissionPercentage;
}

abstract contract YlideStorage {
	Storage internal s;

	// Registry events
	event KeyAttached(
		address indexed addr,
		uint256 publicKey,
		uint32 keyVersion,
		address registrar,
		uint256 previousEventsIndex
	);

	// Config events
	event MailingFeedOwnershipTransferred(uint256 indexed feedId, address newOwner);
	event BroadcastFeedOwnershipTransferred(uint256 indexed feedId, address newOwner);
	event MailingFeedBeneficiaryChanged(uint256 indexed feedId, address newBeneficiary);
	event BroadcastFeedBeneficiaryChanged(uint256 indexed feedId, address newBeneficiary);
	event BroadcastFeedPublicityChanged(uint256 indexed feedId, bool isPublic);
	event BroadcastFeedWriterChange(uint256 indexed feedId, address indexed writer, bool status);
	event MailingFeedCreated(uint256 indexed feedId, address indexed creator);
	event BroadcastFeedCreated(uint256 indexed feedId, address indexed creator);

	// Mailer events
	event MailPush(
		uint256 indexed recipient,
		uint256 indexed feedId,
		address sender,
		uint256 contentId,
		uint256 previousFeedEventsIndex,
		bytes key,
		bytes supplement,
		bool paidForAttention
	);
	event BroadcastPush(
		address indexed sender,
		uint256 indexed feedId,
		uint256 contentId,
		uint256 previousFeedEventsIndex
	);
	event MessageContent(
		uint256 indexed contentId,
		address indexed sender,
		uint16 parts,
		uint16 partIdx,
		bytes content
	);
	event MailingFeedJoined(
		uint256 indexed feedId,
		uint256 indexed newParticipant,
		uint256 previousFeedJoinEventsIndex
	);

	event StakeClaimed(
		uint256 indexed contentId,
		address indexed token,
		uint256 indexed recipient,
		uint256 recipientShare,
		address interfaceAddress,
		uint256 interfaceCommission,
		address ylideBeneficiary,
		uint256 ylideCommission,
		address registrar,
		uint256 registrarCommission
	);

	event StakeCancelled(
		uint256 indexed contentId,
		address indexed token,
		uint256 indexed recipient,
		uint256 amount
	);

	event WithdrawnRewards(address indexed user, address indexed token, uint256 amount);
}
