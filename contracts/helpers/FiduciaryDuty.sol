// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './Owned.sol';

contract FiduciaryDuty is Owned {

	uint256 public contentPartFee = 0;
    uint256 public recipientFee = 0;
	uint256 public broadcastFee = 0;
    address payable public beneficiary;

    constructor() {
        beneficiary = payable(msg.sender);
    }

	function setFees(uint256 _contentPartFee, uint256 _recipientFee, uint256 _broadcastFee) public onlyOwner {
        contentPartFee = _contentPartFee;
        recipientFee = _recipientFee;
		broadcastFee = _broadcastFee;
    }

    function setBeneficiary(address payable _beneficiary) public onlyOwner {
        beneficiary = _beneficiary;
    }

	function payOut(uint256 contentParts, uint256 recipients, uint256 broadcasts) internal virtual {
		uint256 totalValue = contentPartFee * contentParts + recipientFee * recipients + broadcastFee * broadcasts;
		if (totalValue > 0) {
			beneficiary.transfer(totalValue);
		}
	}

}