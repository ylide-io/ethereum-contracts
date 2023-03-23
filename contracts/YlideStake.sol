// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {IERC721MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IYlideMailer} from "./interfaces/IYlideMailer.sol";
import {IYlideTokenAttachment} from "./interfaces/IYlideTokenAttachment.sol";

contract YlideStake is
	IYlideTokenAttachment,
	OwnableUpgradeable,
	PausableUpgradeable,
	UUPSUpgradeable
{
	using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

	uint256 public constant version = 1;

	IYlideMailer public ylideMailer;

	// contentId => recipient => TokenInfo
	mapping(uint256 => mapping(address => TokenInfo)) contentIdToUserToTokenInfo;

	struct TokenInfo {
		uint256 amountOrTokenId;
		address recipient;
		address token;
		TokenType tokenType;
		bool claimed;
	}

	event TokenClaim(
		uint256 indexed contentId,
		uint256 amountOrTokenId,
		address indexed recipient,
		address indexed token,
		TokenType tokenType
	);

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize() public initializer {
		__Ownable_init();
		__Pausable_init();
	}

	function _authorizeUpgrade(
		address newImplementation
	) internal virtual override onlyOwner whenPaused {}

	function setYlideMailer(IYlideMailer _ylideMailer) external onlyOwner {
		ylideMailer = _ylideMailer;
	}

	function _stake(TransferInfo calldata transferInfo, uint256 contentId) internal {
		if (transferInfo.tokenType == TokenType.ERC20) {
			IERC20MetadataUpgradeable(transferInfo.token).safeTransferFrom(
				msg.sender,
				address(this),
				transferInfo.amountOrTokenId
			);
		} else if (transferInfo.tokenType == TokenType.ERC721) {
			IERC721MetadataUpgradeable(transferInfo.token).safeTransferFrom(
				msg.sender,
				address(this),
				transferInfo.amountOrTokenId
			);
		}
		// TODO: ensure it will be not overwritten
		contentIdToUserToTokenInfo[contentId][transferInfo.recipient] = TokenInfo({
			amountOrTokenId: transferInfo.amountOrTokenId,
			token: transferInfo.token,
			tokenType: transferInfo.tokenType,
			recipient: transferInfo.recipient,
			claimed: false
		});
		emit TokenAttachment(
			contentId,
			transferInfo.amountOrTokenId,
			transferInfo.recipient,
			msg.sender,
			transferInfo.token,
			transferInfo.tokenType
		);
	}

	function _handleTokenAttachment(
		TransferInfo[] calldata transferInfos,
		uint256 contentId
	) internal {
		for (uint256 i; i < transferInfos.length; ) {
			if (transferInfos[i].recipient != address(0)) {
				_stake(transferInfos[i], contentId);
			}
			unchecked {
				i++;
			}
		}
	}

	function sendBulkMailWithToken(
		uint256 feedId,
		uint256 uniqueId,
		uint256[] calldata recipients,
		bytes[] calldata keys,
		bytes calldata content,
		TransferInfo[] calldata transferInfos
	) public payable whenNotPaused returns (uint256) {
		uint256 contentId = ylideMailer.sendBulkMail(
			msg.sender,
			feedId,
			uniqueId,
			recipients,
			keys,
			content
		);
		_handleTokenAttachment(transferInfos, contentId);
		return contentId;
	}

	function addMailRecipientsWithToken(
		uint256 feedId,
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint16 partsCount,
		uint16 blockCountLock,
		uint256[] calldata recipients,
		bytes[] calldata keys,
		TransferInfo[] calldata transferInfos
	) public payable whenNotPaused returns (uint256) {
		uint256 contentId = ylideMailer.addMailRecipients(
			msg.sender,
			feedId,
			uniqueId,
			firstBlockNumber,
			partsCount,
			blockCountLock,
			recipients,
			keys
		);
		_handleTokenAttachment(transferInfos, contentId);
		return contentId;
	}

	function withdraw(uint256[] calldata contentIds) external whenNotPaused {
		for (uint256 i; i < contentIds.length; ) {
			TokenInfo storage tokenInfo = contentIdToUserToTokenInfo[contentIds[i]][msg.sender];
			if (tokenInfo.token == address(0) || tokenInfo.claimed == true) {
				unchecked {
					i++;
				}
				continue;
			}
			if (tokenInfo.tokenType == TokenType.ERC20) {
				IERC20MetadataUpgradeable(tokenInfo.token).safeTransfer(
					msg.sender,
					tokenInfo.amountOrTokenId
				);
			} else if (tokenInfo.tokenType == TokenType.ERC721) {
				IERC721MetadataUpgradeable(tokenInfo.token).safeTransferFrom(
					address(this),
					msg.sender,
					tokenInfo.amountOrTokenId
				);
			}
			tokenInfo.claimed = true;
			emit TokenClaim(
				contentIds[i],
				tokenInfo.amountOrTokenId,
				tokenInfo.recipient,
				tokenInfo.token,
				tokenInfo.tokenType
			);
			unchecked {
				i++;
			}
		}
	}

	function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}

	function onERC721Received(
		address,
		address,
		uint256,
		bytes memory
	) public pure returns (bytes4) {
		return this.onERC721Received.selector;
	}
}
