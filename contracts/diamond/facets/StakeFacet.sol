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

	// ================================
	// =========== Errors =============
	// ================================

	error NotSender();
	error StakeLockUp();
	error NothingToWithdraw();
	error NoRegistrar();

	// ================================
	// ===== External methods =========
	// ================================

	// Called by recipient of message
	function claim(uint256[] calldata contentIds, RecipientInterfaceArgs calldata args) external {
		address registrar = s.addressToPublicKey[msg.sender].registrar;
		if (registrar == address(0)) {
			revert NoRegistrar();
		}
		for (uint256 i; i < contentIds.length; ) {
			TokenInfo storage tokenInfo = s.contentIdToRecipientToTokenInfo[contentIds[i]][
				uint160(msg.sender)
			];
			if (tokenInfo.token == address(0) || tokenInfo.withdrawn) {
				revert NothingToWithdraw();
			}
			uint256 interfaceCommission = (tokenInfo.amount * args.interfaceCommission) / 10000;
			uint256 recipientShare = tokenInfo.amount - interfaceCommission;

			tokenInfo.withdrawn = true;
			s.addressToTokenToAmount[args.interfaceAddress][tokenInfo.token] += interfaceCommission;

			s.addressToTokenToAmount[s.ylideBeneficiary][tokenInfo.token] += tokenInfo
				.ylideCommission;
			s.addressToTokenToAmount[registrar][tokenInfo.token] += tokenInfo.registrarCommission;

			IERC20(tokenInfo.token).safeTransfer(msg.sender, recipientShare);
			unchecked {
				i++;
			}
		}
	}

	// Called by ylide || registrar || recipient interface
	function claim(address token) external {
		uint256 amount = s.addressToTokenToAmount[msg.sender][token];
		if (amount == 0) {
			revert NothingToWithdraw();
		}
		s.addressToTokenToAmount[msg.sender][token] = 0;
		IERC20(token).safeTransfer(msg.sender, amount);
	}

	// called by sender of message
	function cancel(CancelArgs[] calldata args) external {
		for (uint256 i; i < args.length; ) {
			TokenInfo storage tokenInfo = s.contentIdToRecipientToTokenInfo[args[i].contentId][
				uint160(args[i].recipient)
			];
			if (tokenInfo.token == address(0) || tokenInfo.withdrawn) {
				revert NothingToWithdraw();
			}
			if (tokenInfo.sender != msg.sender) {
				revert NotSender();
			}
			if (tokenInfo.stakeBlockedUntil >= block.timestamp) {
				revert StakeLockUp();
			}
			tokenInfo.withdrawn = true;
			IERC20(tokenInfo.token).safeTransfer(
				tokenInfo.sender,
				tokenInfo.amount + tokenInfo.ylideCommission + tokenInfo.registrarCommission
			);
			unchecked {
				i++;
			}
		}
	}
}
