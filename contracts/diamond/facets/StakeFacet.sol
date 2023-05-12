// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {YlideStorage} from "../storage/YlideStorage.sol";
import {TokenInfo} from "../storage/DiamondStorage.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakeFacet is YlideStorage {
	using SafeERC20 for IERC20;

	// ================================
	// ====== Arguments structs =======
	// ================================

	struct RecipientInterfaceArgs {
		address interfaceAddress;
		// Percentages denominated in 1e2. 100% = 10000 wei || 0.27% = 27 wei
		uint256 interfaceCommission;
	}

	struct CancelArgs {
		uint256 contentId;
		address recipient;
	}

	struct PayWallArgs {
		address token;
		uint256 amount;
	}

	struct WhitelistArgs {
		address recipient;
		bool status;
	}

	// ================================
	// =========== Errors =============
	// ================================

	error NotSender();
	error StakeLockUp();
	error AlreadyWithdrawn();

	// ================================
	// ===== Internal methods =========
	// ================================

	function _removeToken(address token, address[] storage tokens) internal {
		for (uint256 i; i < tokens.length; ) {
			if (tokens[i] == token) {
				tokens[i] = tokens[tokens.length - 1];
				tokens.pop();
				return;
			}
			unchecked {
				i++;
			}
		}
	}

	function _setPaywall(PayWallArgs[] calldata args) internal {
		for (uint256 i; i < args.length; ) {
			bool exists = s.recipientToPaywallTokenToAmount[msg.sender][args[i].token] > 0;
			s.recipientToPaywallTokenToAmount[msg.sender][args[i].token] = args[i].amount;
			if (args[i].amount > 0 && !exists) {
				s.recipientToPaywallTokens[msg.sender].push(args[i].token);
			} else if (args[i].amount == 0 && exists) {
				_removeToken(args[i].token, s.recipientToPaywallTokens[msg.sender]);
			}
			unchecked {
				i++;
			}
		}
	}

	function _whitelistSenders(WhitelistArgs[] calldata args) internal {
		for (uint256 i; i < args.length; ) {
			s.recipientToWhitelistedSender[msg.sender][args[i].recipient] = args[i].status;
			unchecked {
				i++;
			}
		}
	}

	// ================================
	// ===== External methods =========
	// ================================

	function setPaywall(PayWallArgs[] calldata payWallArgs) external {
		_setPaywall(payWallArgs);
	}

	function whitelistSenders(WhitelistArgs[] calldata whitelistArgs) external {
		_whitelistSenders(whitelistArgs);
	}

	function setPayWallAndWhiteListSenders(
		PayWallArgs[] calldata payWallArgs,
		WhitelistArgs[] calldata whitelistArgs
	) external {
		_setPaywall(payWallArgs);
		_whitelistSenders(whitelistArgs);
	}

	// Called by recipient of message
	function claim(uint256[] calldata contentIds, RecipientInterfaceArgs calldata args) external {
		address registrar = s.addressToPublicKey[msg.sender].registrar;
		for (uint256 i; i < contentIds.length; ) {
			TokenInfo storage tokenInfo = s.contentIdToRecipientToTokenInfo[contentIds[i]][
				msg.sender
			];
			if (tokenInfo.token == address(0) || tokenInfo.withdrawn) {
				revert AlreadyWithdrawn();
			}
			tokenInfo.withdrawn = true;
			uint256 interfaceCommission = (tokenInfo.amount * args.interfaceCommission) / 100;
			uint256 recipientShare = tokenInfo.amount - interfaceCommission;
			IERC20(tokenInfo.token).safeTransfer(msg.sender, recipientShare);
			IERC20(tokenInfo.token).safeTransfer(args.interfaceAddress, interfaceCommission);
			IERC20(tokenInfo.token).safeTransfer(s.ylideBeneficiary, tokenInfo.ylideCommission);
			IERC20(tokenInfo.token).safeTransfer(registrar, tokenInfo.referrerCommission);
			unchecked {
				i++;
			}
		}
	}

	// called by sender of message
	function cancel(CancelArgs[] calldata args) external {
		for (uint256 i; i < args.length; ) {
			TokenInfo storage tokenInfo = s.contentIdToRecipientToTokenInfo[args[i].contentId][
				args[i].recipient
			];
			if (tokenInfo.token == address(0) || tokenInfo.withdrawn) {
				revert AlreadyWithdrawn();
			}
			if (tokenInfo.sender != msg.sender) {
				revert NotSender();
			}
			if (tokenInfo.stakeBlockedUntil <= block.number) {
				revert StakeLockUp();
			}
			tokenInfo.withdrawn = true;
			IERC20(tokenInfo.token).safeTransfer(
				tokenInfo.sender,
				tokenInfo.amount + tokenInfo.ylideCommission + tokenInfo.referrerCommission
			);
			unchecked {
				i++;
			}
		}
	}
}
