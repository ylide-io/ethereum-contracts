// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract YlideRegistryV1 {

    event PublicKeyToAddress(uint256 indexed publicKey, address addr);
    event AddressToPublicKey(address indexed addr, uint256 publicKey);

    constructor() {
    }

    function attachPublicKey(uint256 publicKey) public {
        emit AddressToPublicKey(msg.sender, publicKey);
    }

    function attachAddress(uint256 publicKey) public {
        emit PublicKeyToAddress(publicKey, msg.sender);
    }

}