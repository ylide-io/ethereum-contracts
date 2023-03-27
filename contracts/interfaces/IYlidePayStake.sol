// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IYlideTokenAttachment} from "./IYlideTokenAttachment.sol";

interface IYlidePayStake is IYlideTokenAttachment {
	struct TransferInfo {
		uint256 amountOrTokenId;
		address recipient;
		address token;
		TokenType tokenType;
	}

	enum TokenType {
		ERC20,
		ERC721
	}

	event TokenAttachment(
		uint256 indexed contentId,
		uint256 amountOrTokenId,
		address indexed recipient,
		address indexed sender,
		address token,
		TokenType tokenType
	);
}
