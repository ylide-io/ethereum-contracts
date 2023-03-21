// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

library ListMap {
	struct _uint256 {
		uint256[] list;
		mapping(uint256 => bool) includes;
	}

	struct _address {
		address[] list;
		mapping(address => bool) includes;
	}

	/**
	 * @dev remove item
	 * @param listMap listMap which should be changed
	 * @param value item to remove from listMap
	 */
	function remove(_uint256 storage listMap, uint256 value) internal {
		for (uint256 i; i < listMap.list.length; i++) {
			if (listMap.list[i] == value) {
				listMap.list[i] = listMap.list[listMap.list.length - 1];
				listMap.list.pop();
				listMap.includes[value] = false;
				return;
			}
		}
		revert("Not in list map");
	}

	/**
	 * @dev remove item
	 * @param listMap listMap which should be changed
	 * @param value item to remove from listMap
	 */
	function remove(_address storage listMap, address value) internal {
		for (uint256 i; i < listMap.list.length; i++) {
			if (listMap.list[i] == value) {
				listMap.list[i] = listMap.list[listMap.list.length - 1];
				listMap.list.pop();
				listMap.includes[value] = false;
				return;
			}
		}
		revert("Not in list map");
	}

	/**
	 * @dev add item
	 * @param listMap listMap which should be changed
	 * @param value item to add to listMap
	 */
	function add(_uint256 storage listMap, uint256 value) internal {
		if (listMap.includes[value]) {
			revert("Already in list map");
		}
		listMap.includes[value] = true;
		listMap.list.push(value);
	}

	/**
	 * @dev add item
	 * @param listMap listMap which should be changed
	 * @param value item to add to listMap
	 */
	function add(_address storage listMap, address value) internal {
		if (listMap.includes[value]) {
			revert("Already in list map");
		}
		listMap.includes[value] = true;
		listMap.list.push(value);
	}
}
