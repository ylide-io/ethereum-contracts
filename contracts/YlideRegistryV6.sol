// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import './helpers/Owned.sol';
import './helpers/BlockNumberRingBufferIndex.sol';

struct RegistryEntry {
    uint256 previousEventsIndex;
    uint256 publicKey;
    uint64 block;
    uint64 timestamp;
    uint64 keyVersion;
}

contract YlideRegistryV6 is Owned, BlockNumberRingBufferIndex {
    uint256 public version = 6;

    event KeyAttached(address indexed addr, uint256 publicKey, uint64 keyVersion, uint256 previousEventsIndex);
    
    mapping(address => RegistryEntry) public addressToPublicKey;
    mapping(address => bool) public bonucers;

    uint256 public newcomerBonus = 0;
    uint256 public referrerBonus = 0;

    bytes16 private constant _SYMBOLS = "0123456789abcdef";

    constructor() {
        bonucers[msg.sender] = true;
    }

    function getPublicKey(address addr) view public returns (RegistryEntry memory entry) {
        entry = addressToPublicKey[addr];
    }

    modifier onlyBonucer() {
        if (bonucers[msg.sender] != true) {
            revert();
        }
        _;
    }

    function setBonucer(address newBonucer, bool val) public onlyOwner {
        if (newBonucer != address(0)) {
            bonucers[newBonucer] = val;
        }
    }

    function setBonuses(uint256 _newcomerBonus, uint256 _referrerBonus) public onlyOwner {
        newcomerBonus = _newcomerBonus;
        referrerBonus = _referrerBonus;
    }

    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            string memory buffer = new string(10);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, 10))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), _SYMBOLS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    function iToHex(bytes32 buffer) public pure returns (bytes memory) {
        bytes memory converted = new bytes(64);
        bytes memory _base = "0123456789abcdef";

        for (uint8 i = 0; i < 32; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return converted;
    }

    function verifyMessage(bytes32 publicKey, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n64";
        bytes memory _msg = iToHex(publicKey);
        bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, _msg));
        address signer = ecrecover(prefixedHashMessage, _v, _r, _s);
        return signer;
    }

    receive() external payable {
        // do nothing
    }

    function internalKeyAttach(address addr, uint256 publicKey, uint64 keyVersion) internal {
        uint256 index = 0;
        if (addressToPublicKey[addr].keyVersion != 0) {
            index = storeBlockNumber(addressToPublicKey[addr].previousEventsIndex, addressToPublicKey[addr].block / 128);
        }

        addressToPublicKey[addr] = RegistryEntry(index, publicKey, uint64(block.number), uint64(block.timestamp), keyVersion);
        emit KeyAttached(addr, publicKey, keyVersion, index);
    }

    function attachPublicKey(uint256 publicKey, uint64 keyVersion) public {
        require(keyVersion != 0, 'Key version must be above zero');

        internalKeyAttach(msg.sender, publicKey, keyVersion);
    }

    function attachPublicKeyByAdmin(uint8 _v, bytes32 _r, bytes32 _s, address payable addr, uint256 publicKey, uint64 keyVersion, address payable referrer, bool payBonus) external payable onlyBonucer {
        require(keyVersion != 0, 'Key version must be above zero');
        require(verifyMessage(bytes32(publicKey), _v, _r, _s) == addr, 'Signature does not match the user''s address');
        require(referrer == address(0x0) || addressToPublicKey[referrer].keyVersion != 0, 'Referrer must be registered');
        require(addr != address(0x0) && addressToPublicKey[addr].keyVersion == 0, 'Only new user key can be assigned by admin');

        internalKeyAttach(addr, publicKey, keyVersion);

        if (payBonus && newcomerBonus != 0) {
            addr.transfer(newcomerBonus);
        }
        if (referrer != address(0x0) && referrerBonus != 0) {
            referrer.transfer(referrerBonus);
        }
    }
}