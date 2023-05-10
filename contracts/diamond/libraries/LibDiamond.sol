// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {DiamondStorage} from "../storage/DiamondStorage.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";

// Remember to add the loupe functions from DiamondLoupeFacet to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard
library LibDiamond {
	event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);

	error InitializationFunctionReverted(address _initializationContractAddress, bytes _calldata);

	// Internal function version of diamondCut
	function diamondCut(
		DiamondStorage storage s,
		IDiamondCut.FacetCut[] memory _diamondCut,
		address _init,
		bytes memory _calldata
	) internal {
		for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
			IDiamondCut.FacetCutAction action = _diamondCut[facetIndex].action;
			if (action == IDiamondCut.FacetCutAction.Add) {
				addFunctions(
					s,
					_diamondCut[facetIndex].facetAddress,
					_diamondCut[facetIndex].functionSelectors
				);
			} else if (action == IDiamondCut.FacetCutAction.Replace) {
				replaceFunctions(
					s,
					_diamondCut[facetIndex].facetAddress,
					_diamondCut[facetIndex].functionSelectors
				);
			} else if (action == IDiamondCut.FacetCutAction.Remove) {
				removeFunctions(
					s,
					_diamondCut[facetIndex].facetAddress,
					_diamondCut[facetIndex].functionSelectors
				);
			} else {
				revert("LibDiamondCut: Incorrect FacetCutAction");
			}
		}
		emit DiamondCut(_diamondCut, _init, _calldata);
		initializeDiamondCut(_init, _calldata);
	}

	function addFunctions(
		DiamondStorage storage s,
		address _facetAddress,
		bytes4[] memory _functionSelectors
	) internal {
		require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
		require(_facetAddress != address(0), "LibDiamondCut: Add facet can't be address(0)");
		uint96 selectorPosition = uint96(
			s.facetFunctionSelectors[_facetAddress].functionSelectors.length
		);
		// add new facet address if it does not exist
		if (selectorPosition == 0) {
			addFacet(s, _facetAddress);
		}
		for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
			bytes4 selector = _functionSelectors[selectorIndex];
			address oldFacetAddress = s.selectorToFacetAndPosition[selector].facetAddress;
			require(
				oldFacetAddress == address(0),
				"LibDiamondCut: Can't add function that already exists"
			);
			addFunction(s, selector, selectorPosition, _facetAddress);
			selectorPosition++;
		}
	}

	function replaceFunctions(
		DiamondStorage storage s,
		address _facetAddress,
		bytes4[] memory _functionSelectors
	) internal {
		require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
		require(_facetAddress != address(0), "LibDiamondCut: Add facet can't be address(0)");
		uint96 selectorPosition = uint96(
			s.facetFunctionSelectors[_facetAddress].functionSelectors.length
		);
		// add new facet address if it does not exist
		if (selectorPosition == 0) {
			addFacet(s, _facetAddress);
		}
		for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
			bytes4 selector = _functionSelectors[selectorIndex];
			address oldFacetAddress = s.selectorToFacetAndPosition[selector].facetAddress;
			require(
				oldFacetAddress != _facetAddress,
				"LibDiamondCut: Can't replace function with same function"
			);
			removeFunction(s, oldFacetAddress, selector);
			addFunction(s, selector, selectorPosition, _facetAddress);
			selectorPosition++;
		}
	}

	function removeFunctions(
		DiamondStorage storage s,
		address _facetAddress,
		bytes4[] memory _functionSelectors
	) internal {
		require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
		// if function does not exist then do nothing and return
		require(
			_facetAddress == address(0),
			"LibDiamondCut: Remove facet address must be address(0)"
		);
		for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
			bytes4 selector = _functionSelectors[selectorIndex];
			address oldFacetAddress = s.selectorToFacetAndPosition[selector].facetAddress;
			removeFunction(s, oldFacetAddress, selector);
		}
	}

	function addFacet(DiamondStorage storage s, address _facetAddress) internal {
		enforceHasContractCode(_facetAddress, "LibDiamondCut: New facet has no code");
		s.facetFunctionSelectors[_facetAddress].facetAddressPosition = s.facetAddresses.length;
		s.facetAddresses.push(_facetAddress);
	}

	function addFunction(
		DiamondStorage storage s,
		bytes4 _selector,
		uint96 _selectorPosition,
		address _facetAddress
	) internal {
		s.selectorToFacetAndPosition[_selector].functionSelectorPosition = _selectorPosition;
		s.facetFunctionSelectors[_facetAddress].functionSelectors.push(_selector);
		s.selectorToFacetAndPosition[_selector].facetAddress = _facetAddress;
	}

	function removeFunction(
		DiamondStorage storage s,
		address _facetAddress,
		bytes4 _selector
	) internal {
		require(
			_facetAddress != address(0),
			"LibDiamondCut: Can't remove function that doesn't exist"
		);
		// an immutable function is a function defined directly in a diamond
		require(_facetAddress != address(this), "LibDiamondCut: Can't remove immutable function");
		// replace selector with last selector, then delete last selector
		uint256 selectorPosition = s.selectorToFacetAndPosition[_selector].functionSelectorPosition;
		uint256 lastSelectorPosition = s
			.facetFunctionSelectors[_facetAddress]
			.functionSelectors
			.length - 1;
		// if not the same then replace _selector with lastSelector
		if (selectorPosition != lastSelectorPosition) {
			bytes4 lastSelector = s.facetFunctionSelectors[_facetAddress].functionSelectors[
				lastSelectorPosition
			];
			s.facetFunctionSelectors[_facetAddress].functionSelectors[
				selectorPosition
			] = lastSelector;
			s.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = uint96(
				selectorPosition
			);
		}
		// delete the last selector
		s.facetFunctionSelectors[_facetAddress].functionSelectors.pop();
		delete s.selectorToFacetAndPosition[_selector];

		// if no more selectors for facet address then delete the facet address
		if (lastSelectorPosition == 0) {
			// replace facet address with last facet address and delete last facet address
			uint256 lastFacetAddressPosition = s.facetAddresses.length - 1;
			uint256 facetAddressPosition = s
				.facetFunctionSelectors[_facetAddress]
				.facetAddressPosition;
			if (facetAddressPosition != lastFacetAddressPosition) {
				address lastFacetAddress = s.facetAddresses[lastFacetAddressPosition];
				s.facetAddresses[facetAddressPosition] = lastFacetAddress;
				s
					.facetFunctionSelectors[lastFacetAddress]
					.facetAddressPosition = facetAddressPosition;
			}
			s.facetAddresses.pop();
			delete s.facetFunctionSelectors[_facetAddress].facetAddressPosition;
		}
	}

	function initializeDiamondCut(address _init, bytes memory _calldata) internal {
		if (_init == address(0)) {
			return;
		}
		enforceHasContractCode(_init, "LibDiamondCut: _init address has no code");
		(bool success, bytes memory error) = _init.delegatecall(_calldata);
		if (!success) {
			if (error.length > 0) {
				// bubble up error
				/// @solidity memory-safe-assembly
				assembly {
					let returndata_size := mload(error)
					revert(add(32, error), returndata_size)
				}
			} else {
				revert InitializationFunctionReverted(_init, _calldata);
			}
		}
	}

	function enforceHasContractCode(address _contract, string memory _errorMessage) internal view {
		uint256 contractSize;
		assembly {
			contractSize := extcodesize(_contract)
		}
		require(contractSize > 0, _errorMessage);
	}
}
