// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import './helpers/Owned.sol';
import './helpers/Terminatable.sol';
import './helpers/BlockNumberRingBufferIndex.sol';

struct RegistryEntryV6 {
    uint256 previousEventsIndex;
    uint256 publicKey;
    uint64 block;
    uint64 timestamp;
    uint32 keyVersion;
    uint32 registrar;
}

contract YlideRegistryV6 is Owned, Terminatable, BlockNumberRingBufferIndex {
    uint256 public version = 6;

    event KeyAttached(address indexed addr, uint256 publicKey, uint32 keyVersion, uint32 registrar, uint256 previousEventsIndex);
    
    mapping(address => RegistryEntryV6) public addressToPublicKey;
    mapping(address => bool) public bonucers;

    uint256 public newcomerBonus = 0;
    uint256 public referrerBonus = 0;

    bytes16 private constant _SYMBOLS = "0123456789abcdef";

    constructor() {
        bonucers[msg.sender] = true;
    }

    function getPublicKey(address addr) view public returns (RegistryEntryV6 memory entry) {
        entry = addressToPublicKey[addr];
    }

    modifier onlyBonucer() {
        if (bonucers[msg.sender] != true) {
            revert();
        }
        _;
    }

    function setBonucer(address newBonucer, bool val) public onlyOwner notTerminated {
        if (newBonucer != address(0)) {
            bonucers[newBonucer] = val;
        }
    }

    function setBonuses(uint256 _newcomerBonus, uint256 _referrerBonus) public onlyOwner notTerminated {
        newcomerBonus = _newcomerBonus;
        referrerBonus = _referrerBonus;
    }

    function uint256ToHex(bytes32 buffer) public pure returns (bytes memory) {
        bytes memory converted = new bytes(64);
        bytes memory _base = "0123456789abcdef";

        for (uint8 i = 0; i < 32; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return converted;
    }

    function uint32ToHex(bytes4 buffer) public pure returns (bytes memory) {
        bytes memory converted = new bytes(8);
        bytes memory _base = "0123456789abcdef";

        for (uint8 i = 0; i < 4; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return converted;
    }

    function uint64ToHex(bytes8 buffer) public pure returns (bytes memory) {
        bytes memory converted = new bytes(16);
        bytes memory _base = "0123456789abcdef";

        for (uint8 i = 0; i < 8; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return converted;
    }

    function verifyMessage(bytes32 publicKey, uint8 _v, bytes32 _r, bytes32 _s, uint32 registrar, uint64 timestampLock) public view returns (address) {
        if (timestampLock > block.timestamp || block.timestamp - timestampLock > 5 * 60) {
            revert('Timestamp lock is invalid');
        }
        bytes memory prefix = "\x19Ethereum Signed Message:\n330";
        // (121 + 2) + (14 + 64 + 1) + (13 + 8 + 1) + (12 + 64 + 1) + (13 + 16 + 0)
        bytes memory _msg = abi.encodePacked(
            "I authorize Ylide Faucet to publish my public key on my behalf to eliminate gas costs on my transaction for five minutes.\n\n", 
            "Public key: 0x", uint256ToHex(publicKey), "\n",
            "Registrar: 0x", uint32ToHex(bytes4(registrar)), "\n",
            "Chain ID: 0x", uint256ToHex(bytes32(block.chainid)), "\n",
            "Timestamp: 0x", uint64ToHex(bytes8(timestampLock))
        );
        bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, _msg));
        address signer = ecrecover(prefixedHashMessage, _v, _r, _s);
        return signer;
    }

    receive() external payable {
        // do nothing
    }

    function internalKeyAttach(address addr, uint256 publicKey, uint32 keyVersion, uint32 registrar) internal {
        uint256 index = 0;
        if (addressToPublicKey[addr].keyVersion != 0) {
            index = storeBlockNumber(addressToPublicKey[addr].previousEventsIndex, addressToPublicKey[addr].block / 128);
        }

        addressToPublicKey[addr] = RegistryEntryV6(index, publicKey, uint64(block.number), uint64(block.timestamp), keyVersion, registrar);
        emit KeyAttached(addr, publicKey, keyVersion, registrar, index);
    }

    function attachPublicKey(uint256 publicKey, uint32 keyVersion, uint32 registrar) public notTerminated {
        require(keyVersion != 0, 'Key version must be above zero');

        internalKeyAttach(msg.sender, publicKey, keyVersion, registrar);
    }

    function attachPublicKeyByAdmin(uint8 _v, bytes32 _r, bytes32 _s, address payable addr, uint256 publicKey, uint32 keyVersion, uint32 registrar, uint64 timestampLock, address payable referrer, bool payBonus) external payable onlyBonucer notTerminated {
        require(keyVersion != 0, 'Key version must be above zero');
        require(verifyMessage(bytes32(publicKey), _v, _r, _s, registrar, timestampLock) == addr, 'Signature does not match the user''s address');
        require(referrer == address(0x0) || addressToPublicKey[referrer].keyVersion != 0, 'Referrer must be registered');
        require(addr != address(0x0) && addressToPublicKey[addr].keyVersion == 0, 'Only new user key can be assigned by admin');

        internalKeyAttach(addr, publicKey, keyVersion, registrar);

        if (payBonus && newcomerBonus != 0) {
            addr.transfer(newcomerBonus);
        }
        if (referrer != address(0x0) && referrerBonus != 0) {
            referrer.transfer(referrerBonus);
        }
    }
}