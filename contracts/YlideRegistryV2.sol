// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract YlideRegistryV2 {
    mapping(address => uint256) public addressToPublicKey;
    mapping(uint256 => address) public publicKeyToAddress;

    constructor() {}

    // function getPublicKey(address addr) public view returns (uint256 publicKey) {
    //     return addressToPublicKey[addr];
    // }

    // function getAddress(uint256 publicKey) public view returns (address addr) {
    //     return publicKeyToAddress[publicKey];
    // }

    function attachPublicKey(uint256 publicKey) public {
        addressToPublicKey[msg.sender] = publicKey;
    }

    function attachAddress(uint256 publicKey) public {
        publicKeyToAddress[publicKey] = msg.sender;
    }
}