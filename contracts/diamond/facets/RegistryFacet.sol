// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {YlideStorage, RegistryEntry} from "../YlideStorage.sol";
import {Hex} from "../libraries/Hex.sol";
import {RingBufferIndex} from "../libraries/RingBufferIndex.sol";

contract RegistryFacet is YlideStorage {
	// ================================
	// =========== Errors =============
	// ================================
	error TimestampFuture();
	error TimestampOld();
	error KeyVersionInvalid();
	error IsNotBouncer();
	error SignatureInvalid();
	error ReferrerNotRegistered();
	error UserExists();
	error NoRegistrar();

	// ================================
	// ===== Internal methods =========
	// ================================

	function verifyMessage(
		bytes32 publicKey,
		uint8 _v,
		bytes32 _r,
		bytes32 _s,
		address registrar,
		uint64 timestampLock
	) internal view returns (address) {
		if (timestampLock > block.timestamp) {
			revert TimestampFuture();
		}
		if (block.timestamp - timestampLock > 5 * 60) {
			revert TimestampOld();
		}
		bytes memory prefix = "\x19Ethereum Signed Message:\n330";
		// (121 + 2) + (14 + 64 + 1) + (13 + 8 + 1) + (12 + 64 + 1) + (13 + 16 + 0)
		bytes memory _msg = abi.encodePacked(
			"I authorize Ylide Faucet to publish my public key on my behalf to eliminate gas costs on my transaction for five minutes.\n\n",
			"Public key: 0x",
			Hex.uint256ToHex(publicKey),
			"\n",
			"Registrar: 0x",
			Hex.uint256ToHex(bytes32(uint256(uint160(registrar)))),
			"\n",
			"Chain ID: 0x",
			Hex.uint256ToHex(bytes32(block.chainid)),
			"\n",
			"Timestamp: 0x",
			Hex.uint64ToHex(bytes8(timestampLock))
		);
		bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, _msg));
		address signer = ecrecover(prefixedHashMessage, _v, _r, _s);
		return signer;
	}

	function internalKeyAttach(
		address addr,
		uint256 publicKey,
		uint32 keyVersion,
		address registrar
	) internal {
		uint256 index = 0;
		if (s.addressToPublicKey[addr].keyVersion != 0) {
			index = RingBufferIndex.storeBlockNumber(
				s.addressToPublicKey[addr].previousEventsIndex,
				s.addressToPublicKey[addr].block / 128
			);
		}

		s.addressToPublicKey[addr] = RegistryEntry(
			index,
			publicKey,
			uint64(block.number),
			uint64(block.timestamp),
			keyVersion,
			registrar
		);
		// TODO: white list oneself during key attachment?
		s.recipientToWhitelistedSender[uint160(addr)][addr] = true;
		s.recipientToWhitelistedSender[uint256(sha256(abi.encode(addr)))][addr] = true;
		emit KeyAttached(addr, publicKey, keyVersion, registrar, index);
	}

	// ================================
	// ===== External methods =========
	// ================================

	function attachPublicKey(uint256 publicKey, uint32 keyVersion, address registrar) external {
		if (keyVersion == 0) {
			revert KeyVersionInvalid();
		}
		if (registrar == address(0)) {
			revert NoRegistrar();
		}
		internalKeyAttach(msg.sender, publicKey, keyVersion, registrar);
	}

	function attachPublicKeyByAdmin(
		uint8 _v,
		bytes32 _r,
		bytes32 _s,
		address payable addr,
		uint256 publicKey,
		uint32 keyVersion,
		address registrar,
		uint64 timestampLock,
		address payable referrer,
		bool payBonus
	) external payable {
		if (s.bouncers[msg.sender] != true) {
			revert IsNotBouncer();
		}
		if (keyVersion == 0) {
			revert KeyVersionInvalid();
		}
		if (verifyMessage(bytes32(publicKey), _v, _r, _s, registrar, timestampLock) != addr) {
			revert SignatureInvalid();
		}
		if (referrer != address(0) || s.addressToPublicKey[referrer].keyVersion == 0) {
			revert ReferrerNotRegistered();
		}
		if (addr == address(0x0) && s.addressToPublicKey[addr].keyVersion != 0) {
			revert UserExists();
		}

		internalKeyAttach(addr, publicKey, keyVersion, registrar);

		if (payBonus && s.newcomerBonus != 0) {
			addr.transfer(s.newcomerBonus);
		}
		if (referrer != address(0x0) && s.referrerBonus != 0) {
			referrer.transfer(s.referrerBonus);
		}
	}
}
