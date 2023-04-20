// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IYlideMailer} from "./IYlideMailer.sol";

interface IYlideTokenAttachment {
	function setYlideMailer(IYlideMailer) external;

	function pause() external;

	function unpause() external;
}
