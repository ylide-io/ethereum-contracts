export const sendBulkMailSelector =
	'sendBulkMail((uint256,uint256,uint256[],bytes[],bytes),(bytes,uint256,uint256,address),(address,uint8))';

export const addMailRecipientsSelector =
	'addMailRecipients((uint256,uint256,uint256,uint16,uint16,uint256[],bytes[]),(bytes,uint256,uint256,address),(address,uint8))';

export const SendBulkMailTypes = {
	SendBulkMail: [
		{ name: 'feedId', type: 'uint256' },
		{ name: 'uniqueId', type: 'uint256' },
		{ name: 'nonce', type: 'uint256' },
		{ name: 'deadline', type: 'uint256' },
		{ name: 'recipients', type: 'uint256[]' },
		{ name: 'keys', type: 'bytes' },
		{ name: 'content', type: 'bytes' },
		{ name: 'contractAddress', type: 'address' },
		{ name: 'contractType', type: 'uint8' },
	],
};

export const AddMailRecipientsTypes = {
	AddMailRecipients: [
		{ name: 'feedId', type: 'uint256' },
		{ name: 'uniqueId', type: 'uint256' },
		{ name: 'firstBlockNumber', type: 'uint256' },
		{ name: 'nonce', type: 'uint256' },
		{ name: 'deadline', type: 'uint256' },
		{ name: 'partsCount', type: 'uint16' },
		{ name: 'blockCountLock', type: 'uint16' },
		{ name: 'recipients', type: 'uint256[]' },
		{ name: 'keys', type: 'bytes' },
		{ name: 'contractAddress', type: 'address' },
		{ name: 'contractType', type: 'uint8' },
	],
};
