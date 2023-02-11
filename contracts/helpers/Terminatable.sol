// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import './Owned.sol';

contract Terminatable is Owned {
    uint256 public terminationBlock;
    uint256 public creationBlock;

    constructor() {
        terminationBlock = 0;
        creationBlock = block.number;
    }

    modifier notTerminated() {
        if (terminationBlock != 0 && block.number >= terminationBlock) {
            revert();
        }
        _;
    }

    // intendedly left non-blocked to allow reassignment of termination block
    function gracefullyTerminateAt(uint256 blockNumber) public onlyOwner {
        terminationBlock = blockNumber;
    }
}