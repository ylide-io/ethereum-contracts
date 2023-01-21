// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

struct RegistryEntry {
   uint256 publicKey;
   uint128 block;
   uint64 timestamp;
   uint64 keyVersion;
}

contract YlideRegistryV3 {

    uint256 public version = 3;

    event KeyAttached(address indexed addr, uint256 publicKey, uint64 keyVersion);
    
    mapping(address => RegistryEntry) public addressToPublicKey;

    YlideRegistryV3 previousContract;

    constructor(address previousContractAddress) {
        previousContract = YlideRegistryV3(previousContractAddress);
    }

    function getPublicKey(address addr) view public returns (RegistryEntry memory entry, uint contractVersion, address contractAddress) {
        contractVersion = version;
        contractAddress = address(this);
        entry = addressToPublicKey[addr];
        if (entry.keyVersion == 0 && address(previousContract) != address(0x0)) {
            return previousContract.getPublicKey(addr);
        }
    }

    function attachPublicKey(uint256 publicKey, uint64 keyVersion) public {
        addressToPublicKey[msg.sender] = RegistryEntry(publicKey, uint128(block.number), uint64(block.timestamp), keyVersion);

        emit KeyAttached(msg.sender, publicKey, keyVersion);
    }
}