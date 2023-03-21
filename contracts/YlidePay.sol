// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {Owned} from "./helpers/Owned.sol";
import {ListMap} from "./helpers/ListMap.sol";

import {IYlideMailer} from "./interfaces/IYlideMailer.sol";

contract YlidePay is Owned {
	using SafeERC20 for IERC20;
	using ListMap for ListMap._uint256;
	using ListMap for ListMap._address;

	uint256 public constant version = 1;

	IYlideMailer public ylideMailer;

	// user => (token => amount)
	mapping(address => mapping(address => uint256)) erc20Balances;
	// user => (token => tokenId[])
	mapping(address => mapping(address => ListMap._uint256)) erc721Balances;
	// user => token[] - ERC20
	mapping(address => ListMap._address) userErc20Tokens;
	// user => token[] - ERC721
	mapping(address => ListMap._address) userErc721Tokens;

	struct UserInfo {
		uint256 recipient;
		uint256 amountOrTokenId;
		address sendTo;
		address token;
		TokenType tokenType;
		TransferType transferType;
	}

	enum TokenType {
		ERC20,
		ERC721
	}

	enum TransferType {
		Direct,
		Stacking,
		Streaming
	}

	struct WithdrawERC721 {
		address token;
		uint256 tokenId;
	}

	constructor() {}

	function getBalanceErc20(address user, address token) external view returns (uint256) {
		return erc20Balances[user][token];
	}

	function getTokenIdsErc721(
		address user,
		address token
	) external view returns (uint256[] memory) {
		return erc721Balances[user][token].list;
	}

	function getUserErc20Tokens(address user) external view returns (address[] memory) {
		return userErc20Tokens[user].list;
	}

	function getUserErc721Tokens(address user) external view returns (address[] memory) {
		return userErc721Tokens[user].list;
	}

	function setYlideMailer(IYlideMailer _ylideMailer) external onlyOwner {
		ylideMailer = _ylideMailer;
	}

	function _safeTransferFrom(UserInfo calldata userInfo) internal {
		if (userInfo.tokenType == TokenType.ERC20) {
			IERC20(userInfo.token).safeTransferFrom(
				msg.sender,
				userInfo.sendTo,
				userInfo.amountOrTokenId
			);
		} else if (userInfo.tokenType == TokenType.ERC721) {
			IERC721(userInfo.token).safeTransferFrom(
				msg.sender,
				userInfo.sendTo,
				userInfo.amountOrTokenId
			);
		}
	}

	function _stake(UserInfo calldata userInfo) internal {
		if (userInfo.tokenType == TokenType.ERC20) {
			erc20Balances[userInfo.sendTo][userInfo.token] += userInfo.amountOrTokenId;
			if (!userErc20Tokens[userInfo.sendTo].includes[userInfo.token]) {
				userErc20Tokens[userInfo.sendTo].add(userInfo.token);
			}
			IERC20(userInfo.token).safeTransferFrom(
				msg.sender,
				address(this),
				userInfo.amountOrTokenId
			);
		} else if (userInfo.tokenType == TokenType.ERC721) {
			erc721Balances[userInfo.sendTo][userInfo.token].add(userInfo.amountOrTokenId);
			if (!userErc721Tokens[userInfo.sendTo].includes[userInfo.token]) {
				userErc721Tokens[userInfo.sendTo].add(userInfo.token);
			}
			IERC721(userInfo.token).safeTransferFrom(
				msg.sender,
				address(this),
				userInfo.amountOrTokenId
			);
		}
	}

	function _transfer(UserInfo calldata userInfo) internal {
		if (userInfo.sendTo != address(0)) {
			if (userInfo.transferType == TransferType.Direct) {
				_safeTransferFrom(userInfo);
			} else if (userInfo.transferType == TransferType.Stacking) {
				_stake(userInfo);
			}
		}
	}

	function _getRecipientsAndTransfer(
		UserInfo[] calldata userInfos
	) internal returns (uint256[] memory) {
		uint256[] memory recipients = new uint256[](userInfos.length);
		for (uint256 i; i < recipients.length; ) {
			_transfer(userInfos[i]);
			recipients[i] = userInfos[i].recipient;
			unchecked {
				i++;
			}
		}
		return recipients;
	}

	function sendBulkMailWithToken(
		uint256 feedId,
		uint256 uniqueId,
		UserInfo[] calldata userInfos,
		bytes[] calldata keys,
		bytes calldata content
	) public payable returns (uint256) {
		uint256[] memory recipients = _getRecipientsAndTransfer(userInfos);
		uint256 contentId = ylideMailer.sendBulkMail(
			msg.sender,
			feedId,
			uniqueId,
			recipients,
			keys,
			content
		);
		return contentId;
	}

	function addMailRecipientsWithToken(
		uint256 feedId,
		uint256 uniqueId,
		uint256 firstBlockNumber,
		uint16 partsCount,
		uint16 blockCountLock,
		UserInfo[] calldata userInfos,
		bytes[] calldata keys
	) public payable returns (uint256) {
		uint256[] memory recipients = _getRecipientsAndTransfer(userInfos);
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
		return contentId;
	}

	function withdrawErc20(address[] memory erc20s) external {
		for (uint256 i; i < erc20s.length; ) {
			uint256 balance = erc20Balances[msg.sender][erc20s[i]];
			erc20Balances[msg.sender][erc20s[i]] = 0;
			userErc20Tokens[msg.sender].remove(erc20s[i]);
			IERC20(erc20s[i]).safeTransfer(msg.sender, balance);
			unchecked {
				i++;
			}
		}
	}

	function withdrawErc721(WithdrawERC721[] calldata erc721s) external {
		for (uint256 i; i < erc721s.length; ) {
			erc721Balances[msg.sender][erc721s[i].token].remove(erc721s[i].tokenId);
			if (erc721Balances[msg.sender][erc721s[i].token].list.length == 0) {
				userErc721Tokens[msg.sender].remove(erc721s[i].token);
			}
			IERC721(erc721s[i].token).safeTransferFrom(
				address(this),
				msg.sender,
				erc721s[i].tokenId
			);
			unchecked {
				i++;
			}
		}
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
