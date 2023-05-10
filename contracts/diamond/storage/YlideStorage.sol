// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {DiamondStorage} from "./DiamondStorage.sol";

abstract contract YlideStorage {
	DiamondStorage internal s;

	// Registry events
	event KeyAttached(
		address indexed addr,
		uint256 publicKey,
		uint32 keyVersion,
		uint32 registrar,
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
		bytes supplement
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
}
