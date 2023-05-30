// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {YlideStorage, StakeInfoSender, StakeInfoRecipient} from "../YlideStorage.sol";
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
		uint160 recipient;
	}

	struct ClaimVars {
		uint256 interfaceCommission;
		uint256 recipientShare;
		uint256 ylideCommission;
		uint256 registrarCommission;
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
			StakeInfoSender storage stakeInfoSender = s.contentIdToStakeInfoSender[contentIds[i]];
			StakeInfoRecipient storage stakeInfoRecipient = s.contentIdToRecipientToStakeInfo[
				contentIds[i]
			][uint160(msg.sender)];
			if (
				stakeInfoSender.canceled ||
				stakeInfoRecipient.claimed ||
				stakeInfoRecipient.amount == 0
			) {
				revert NothingToWithdraw();
			}

			ClaimVars memory vars;

			vars.interfaceCommission =
				(stakeInfoRecipient.amount * args.interfaceCommission) /
				10000;
			vars.recipientShare = stakeInfoRecipient.amount - vars.interfaceCommission;

			stakeInfoRecipient.claimed = true;

			s.addressToTokenToAmount[args.interfaceAddress][stakeInfoSender.token] += vars
				.interfaceCommission;

			vars.ylideCommission =
				(stakeInfoSender.ylideCommissionPercentage * stakeInfoRecipient.amount) /
				10000;
			s.addressToTokenToAmount[s.ylideBeneficiary][stakeInfoSender.token] += vars
				.ylideCommission;

			uint256 registrarCommission = (stakeInfoRecipient.registrarCommissionPercentage *
				stakeInfoRecipient.amount) / 10000;
			s.addressToTokenToAmount[registrar][stakeInfoSender.token] += registrarCommission;

			IERC20(stakeInfoSender.token).safeTransfer(msg.sender, vars.recipientShare);
			emit StakeClaimed(
				contentIds[i],
				stakeInfoSender.token,
				uint160(msg.sender),
				vars.recipientShare,
				args.interfaceAddress,
				vars.interfaceCommission,
				s.ylideBeneficiary,
				vars.ylideCommission,
				registrar,
				registrarCommission
			);
			unchecked {
				i++;
			}
		}
	}

	// called by sender of message
	function cancel(CancelArgs[] calldata cancelArgs) external {
		for (uint256 i; i < cancelArgs.length; ) {
			StakeInfoSender storage stakeInfoSender = s.contentIdToStakeInfoSender[
				cancelArgs[i].contentId
			];
			StakeInfoRecipient storage stakeInfoRecipient = s.contentIdToRecipientToStakeInfo[
				cancelArgs[i].contentId
			][cancelArgs[i].recipient];
			if (stakeInfoSender.sender != msg.sender) {
				revert NotSender();
			}
			if (stakeInfoSender.canceled || stakeInfoRecipient.claimed) {
				revert NothingToWithdraw();
			}
			if (stakeInfoSender.stakeBlockedUntil >= block.timestamp) {
				revert StakeLockUp();
			}
			stakeInfoSender.canceled = true;

			uint256 ylideCommission = (stakeInfoSender.ylideCommissionPercentage *
				stakeInfoRecipient.amount) / 10000;

			uint256 registrarCommission = (stakeInfoRecipient.registrarCommissionPercentage *
				stakeInfoRecipient.amount) / 10000;

			uint256 wholeAmount = stakeInfoRecipient.amount + ylideCommission + registrarCommission;

			IERC20(stakeInfoSender.token).safeTransfer(stakeInfoSender.sender, wholeAmount);
			emit StakeCancelled(
				cancelArgs[i].contentId,
				stakeInfoSender.token,
				cancelArgs[i].recipient,
				wholeAmount
			);
			unchecked {
				i++;
			}
		}
	}

	// Called by ylide || registrar || recipient interface
	function withdraw(address token) external {
		uint256 amount = s.addressToTokenToAmount[msg.sender][token];
		if (amount == 0) {
			revert NothingToWithdraw();
		}
		s.addressToTokenToAmount[msg.sender][token] = 0;
		IERC20(token).safeTransfer(msg.sender, amount);
		emit WithdrawnRewards(msg.sender, token, amount);
	}
}
