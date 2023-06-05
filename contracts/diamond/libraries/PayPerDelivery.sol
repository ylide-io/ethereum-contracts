// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Storage} from "../YlideStorage.sol";

library PayPerDelivery {
	function calculatePaywall(
		Storage storage s,
		uint256 recipient,
		address sender,
		address token
	) internal view returns (uint256 amount, uint256 ylideCommission, uint256 registrarCommission) {
		amount = calculatePureUserPaywall(s, recipient, sender, token);
		if (amount == 0) {
			return (0, 0, 0);
		}
		ylideCommission = (s.ylideCommissionPercentage * amount) / 10000;
		registrarCommission =
			(s.registrarToCommissionPercentage[
				s.addressToPublicKey[address(uint160(recipient))].registrar
			] * amount) /
			10000;
	}

	function calculatePureUserPaywall(
		Storage storage s,
		uint256 recipient,
		address sender,
		address token
	) internal view returns (uint256 amount) {
		// if sender is whitelisted - allow sending for free
		if (s.recipientToWhitelistedSender[recipient][sender]) {
			return 0;
		}
		uint256 userAmount = s.recipientToPaywallTokenToAmount[recipient][token];
		if (userAmount == 0) {
			amount = s.defaultPaywallTokenToAmount[token];
		} else {
			amount = userAmount;
		}
	}
}
