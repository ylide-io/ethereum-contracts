// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IYlideTokenAttachment {
	enum ContractType {
		Pay,
		Stake,
		StreamSablier
	}

	function contractType() external pure returns (ContractType);

	function setYlideMailer(address) external;

	function pause() external;

	function unpause() external;
}
