// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IYlideMailer} from "./IYlideMailer.sol";

interface IYlideTokenAttachment {
	enum ContractType {
		Pay,
		Stake,
		StreamSablier
	}

	function contractType() external pure returns (ContractType);

	function setYlideMailer(IYlideMailer) external;

	function pause() external;

	function unpause() external;
}
