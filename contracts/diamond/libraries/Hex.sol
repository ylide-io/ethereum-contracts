// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library Hex {
	bytes16 private constant _SYMBOLS = "0123456789abcdef";

	function uint256ToHex(bytes32 buffer) internal pure returns (bytes memory) {
		bytes memory converted = new bytes(64);
		for (uint8 i = 0; i < 32; i++) {
			converted[i * 2] = _SYMBOLS[uint8(buffer[i]) / _SYMBOLS.length];
			converted[i * 2 + 1] = _SYMBOLS[uint8(buffer[i]) % _SYMBOLS.length];
		}

		return converted;
	}

	function uint64ToHex(bytes8 buffer) internal pure returns (bytes memory) {
		bytes memory converted = new bytes(16);
		for (uint8 i = 0; i < 8; i++) {
			converted[i * 2] = _SYMBOLS[uint8(buffer[i]) / _SYMBOLS.length];
			converted[i * 2 + 1] = _SYMBOLS[uint8(buffer[i]) % _SYMBOLS.length];
		}

		return converted;
	}
}
