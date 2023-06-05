// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library ListMap {
	error ElementMissing();
	error ElementExists();

	struct _address {
		address[] list;
		mapping(address => bool) includes;
	}

	function removeList(_address storage listMap, address[] memory list) internal {
		for (uint256 i = 0; i < list.length; i++) {
			remove(listMap, list[i]);
		}
	}

	function remove(_address storage listMap, address value) internal {
		for (uint256 i = 0; i < listMap.list.length; i++) {
			if (listMap.list[i] == value) {
				listMap.list[i] = listMap.list[listMap.list.length - 1];
				listMap.list.pop();
				listMap.includes[value] = false;
				return;
			}
		}
		revert ElementMissing();
	}

	function addList(_address storage listMap, address[] memory list) internal {
		for (uint256 i = 0; i < list.length; i++) {
			add(listMap, list[i]);
		}
	}

	function add(_address storage listMap, address value) internal {
		if (listMap.includes[value]) {
			revert ElementExists();
		}
		listMap.list.push(value);
		listMap.includes[value] = true;
	}
}
