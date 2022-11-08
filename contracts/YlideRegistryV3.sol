// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// import './Owned.sol';

struct RegistryEntry {
   uint256 publicKey;
   uint128 block;
   uint64 timestamp;
   uint64 keyVersion;
}

contract YlideRegistryV3 { //  is Owned

    uint256 public version = 3;

    event KeyAttached(address indexed addr, uint256 publicKey, uint64 keyVersion);
    
    mapping(address => RegistryEntry) public addressToPublicKey;

    YlideRegistryV3 previousContract;

    // uint256 public newcomerBonus = 0;
    // uint256 public referrerBonus = 0;

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

    // function setBonuses(uint256 _newcomerBonus, uint256 _referrerBonus) public onlyOwner {
    //     newcomerBonus = _newcomerBonus;
    //     referrerBonus = _referrerBonus;
    // }

    // function attachPublicKeyByAdmin(address payable addr, uint256 publicKey, address payable referrer) public onlyOwner {
    //     // TODO: make disableable
    //     require(referrer == address(0x0) || addressToPublicKey[referrer].keyVersion == 0, 'Referrer must be registered');
    //     addressToPublicKey[addr] = RegistryEntry(publicKey, uint128(block.number), uint64(block.timestamp), 2);

    //     emit KeyAttached(addr, publicKey, 2);

    //     if (newcomerBonus != 0) {
    //         addr.transfer(newcomerBonus);
    //     }
    //     if (referrer != address(0x0) && referrerBonus != 0) {
    //         referrer.transfer(referrerBonus);
    //     }
    // }
}