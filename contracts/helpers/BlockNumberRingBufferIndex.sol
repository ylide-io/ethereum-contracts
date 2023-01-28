// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract BlockNumberRingBufferIndex {
    
	uint256 constant empty0 = 0x00ff000000ffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant empty1 = 0x00ffffffff000000ffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant empty2 = 0x00ffffffffffffff000000ffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant empty3 = 0x00ffffffffffffffffffff000000ffffffffffffffffffffffffffffffffffff;
    uint256 constant empty4 = 0x00ffffffffffffffffffffffffff000000ffffffffffffffffffffffffffffff;
    uint256 constant empty5 = 0x00ffffffffffffffffffffffffffffffff000000ffffffffffffffffffffffff;
    uint256 constant empty6 = 0x00ffffffffffffffffffffffffffffffffffffff000000ffffffffffffffffff;
    uint256 constant empty7 = 0x00ffffffffffffffffffffffffffffffffffffffffffff000000ffffffffffff;
    uint256 constant empty8 = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffff000000ffffff;
    uint256 constant empty9 = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000;

    uint256 constant indexF = 0xff00000000000000000000000000000000000000000000000000000000000000;

    uint256 constant index1 = 0x0100000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index2 = 0x0200000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index3 = 0x0300000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index4 = 0x0400000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index5 = 0x0500000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index6 = 0x0600000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index7 = 0x0700000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index8 = 0x0800000000000000000000000000000000000000000000000000000000000000;
    uint256 constant index9 = 0x0900000000000000000000000000000000000000000000000000000000000000;

    uint256 constant shift024 = 0x0000000000000000000000000000000000000000000000000000000001000000;
    uint256 constant shift048 = 0x0000000000000000000000000000000000000000000000000001000000000000;
    uint256 constant shift072 = 0x0000000000000000000000000000000000000000000001000000000000000000;
    uint256 constant shift096 = 0x0000000000000000000000000000000000000001000000000000000000000000;
    uint256 constant shift120 = 0x0000000000000000000000000000000001000000000000000000000000000000;
    uint256 constant shift144 = 0x0000000000000000000000000001000000000000000000000000000000000000;
    uint256 constant shift168 = 0x0000000000000000000001000000000000000000000000000000000000000000;
    uint256 constant shift192 = 0x0000000000000001000000000000000000000000000000000000000000000000;
    uint256 constant shift216 = 0x0000000001000000000000000000000000000000000000000000000000000000;

    function storeBlockNumber(uint256 indexValue, uint256 blockNumber) public pure returns (uint256) {
        blockNumber = blockNumber & 0xffffff; // 3 bytes
        uint256 currIdx = indexValue & indexF;
        if (currIdx == 0) {
            return (indexValue & empty1) | index1 | (blockNumber * shift192);
        } else
        if (currIdx == index1) {
            return (indexValue & empty2) | index2 | (blockNumber * shift168);
        } else
        if (currIdx == index2) {
            return (indexValue & empty3) | index3 | (blockNumber * shift144);
        } else
        if (currIdx == index3) {
            return (indexValue & empty4) | index4 | (blockNumber * shift120);
        } else
        if (currIdx == index4) {
            return (indexValue & empty5) | index5 | (blockNumber * shift096);
        } else
        if (currIdx == index5) {
            return (indexValue & empty6) | index6 | (blockNumber * shift072);
        } else
        if (currIdx == index6) {
            return (indexValue & empty7) | index7 | (blockNumber * shift048);
        } else
        if (currIdx == index7) {
            return (indexValue & empty8) | index8 | (blockNumber * shift024);
        } else
        if (currIdx == index8) {
            return (indexValue & empty9) | index9 | blockNumber;
        } else {
            return (indexValue & empty0) | (blockNumber * shift216);
        }
    }
}