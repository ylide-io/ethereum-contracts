// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {YlideStorage} from "./storage/YlideStorage.sol";
import {LibDiamond} from "./libraries/LibDiamond.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";

contract YlideDiamond is YlideStorage {
	constructor(address _contractOwner, address _diamondCutFacet) payable {
		s.contractOwner = _contractOwner;
		s.ylideBeneficiary = payable(_contractOwner);

		// Add the diamondCut external function from the diamondCutFacet
		IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
		bytes4[] memory functionSelectors = new bytes4[](1);
		functionSelectors[0] = IDiamondCut.diamondCut.selector;
		cut[0] = IDiamondCut.FacetCut({
			facetAddress: _diamondCutFacet,
			action: IDiamondCut.FacetCutAction.Add,
			functionSelectors: functionSelectors
		});
		LibDiamond.diamondCut(s, cut, address(0), "");

		// init Registry facet data
		s.bouncers[msg.sender] = true;

		// init Mailer facet data
		s.mailingFeeds[0].owner = msg.sender; // regular mail
		s.mailingFeeds[0].beneficiary = payable(msg.sender);
		s.mailingFeeds[1].owner = msg.sender; // otc mail
		s.mailingFeeds[1].beneficiary = payable(msg.sender);
		s.mailingFeeds[2].owner = msg.sender; // system messages
		s.mailingFeeds[2].beneficiary = payable(msg.sender);
		s.mailingFeeds[3].owner = msg.sender; // system messages
		s.mailingFeeds[3].beneficiary = payable(msg.sender);
		s.mailingFeeds[4].owner = msg.sender; // system messages
		s.mailingFeeds[4].beneficiary = payable(msg.sender);
		s.mailingFeeds[5].owner = msg.sender; // system messages
		s.mailingFeeds[5].beneficiary = payable(msg.sender);
		s.mailingFeeds[6].owner = msg.sender; // system messages
		s.mailingFeeds[6].beneficiary = payable(msg.sender);
		s.mailingFeeds[7].owner = msg.sender; // system messages
		s.mailingFeeds[7].beneficiary = payable(msg.sender);
		s.mailingFeeds[8].owner = msg.sender; // system messages
		s.mailingFeeds[8].beneficiary = payable(msg.sender);
		s.mailingFeeds[9].owner = msg.sender; // system messages
		s.mailingFeeds[9].beneficiary = payable(msg.sender);
		s.mailingFeeds[10].owner = msg.sender; // system messages
		s.mailingFeeds[10].beneficiary = payable(msg.sender);
		s.broadcastFeeds[0].owner = msg.sender;
		s.broadcastFeeds[0].beneficiary = payable(msg.sender);
		s.broadcastFeeds[0].isPublic = false;
		s.broadcastIdToWriters[0][msg.sender] = true;
		s.broadcastFeeds[1].owner = msg.sender;
		s.broadcastFeeds[1].beneficiary = payable(msg.sender);
		s.broadcastFeeds[1].isPublic = false;
		s.broadcastIdToWriters[1][msg.sender] = true;
		s.broadcastFeeds[2].owner = msg.sender;
		s.broadcastFeeds[2].beneficiary = payable(msg.sender);
		s.broadcastFeeds[2].isPublic = true;
	}

	// Find facet for function that is called and execute the
	// function if a facet is found and return any value.
	fallback() external payable {
		// get facet from function selector
		address facet = s.selectorToFacetAndPosition[msg.sig].facetAddress;
		require(facet != address(0), "Diamond: Function does not exist");
		// Execute external function from facet using delegatecall and return any value.
		assembly {
			// copy function selector and any arguments
			calldatacopy(0, 0, calldatasize())
			// execute function call using the facet
			let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
			// get any return value
			returndatacopy(0, 0, returndatasize())
			// return any return value or error back to the caller
			switch result
			case 0 {
				revert(0, returndatasize())
			}
			default {
				return(0, returndatasize())
			}
		}
	}

	receive() external payable {}
}
