// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {YlideStorage} from "../storage/YlideStorage.sol";
import {StakeInfo} from "../storage/DiamondStorage.sol";
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
			StakeInfo storage stakeInfo = s.contentIdToRecipientToStakeInfo[contentIds[i]][
				uint160(msg.sender)
			];
			if (stakeInfo.token == address(0) || stakeInfo.status > 1) {
				revert NothingToWithdraw();
			}
			uint256 interfaceCommission = (stakeInfo.amount * args.interfaceCommission) / 10000;
			uint256 recipientShare = stakeInfo.amount - interfaceCommission;

			stakeInfo.status = 3;
			s.addressToTokenToAmount[args.interfaceAddress][stakeInfo.token] += interfaceCommission;

			s.addressToTokenToAmount[s.ylideBeneficiary][stakeInfo.token] += stakeInfo
				.ylideCommission;
			s.addressToTokenToAmount[registrar][stakeInfo.token] += stakeInfo.registrarCommission;

			IERC20(stakeInfo.token).safeTransfer(msg.sender, recipientShare);
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
			StakeInfo storage stakeInfo = s.contentIdToRecipientToStakeInfo[args[i].contentId][
				uint160(args[i].recipient)
			];
			if (stakeInfo.token == address(0) || stakeInfo.status > 1) {
				revert NothingToWithdraw();
			}
			if (stakeInfo.sender != msg.sender) {
				revert NotSender();
			}
			if (stakeInfo.stakeBlockedUntil >= block.timestamp) {
				revert StakeLockUp();
			}
			stakeInfo.status = 2;
			IERC20(stakeInfo.token).safeTransfer(
				stakeInfo.sender,
				stakeInfo.amount + stakeInfo.ylideCommission + stakeInfo.registrarCommission
			);
			unchecked {
				i++;
			}
		}
	}
}
