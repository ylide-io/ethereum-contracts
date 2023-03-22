import { BigNumberish } from 'ethers';
import { ethers, network } from 'hardhat';
import { YlideMailerV9, YlidePay } from 'typechain-types';
import { Snapshot } from './types';

export function toWei(amount: string | number) {
	return ethers.utils.parseUnits(String(amount), 18);
}

export const makeSnapshot = async (snapshot: Snapshot | undefined): Promise<Snapshot> => {
	const snap = await network.provider.send('evm_snapshot');

	if (snapshot != undefined) {
		snapshot.initial = snap;
		return snapshot;
	}
	return snap;
};

export const backToSnapshot = async (snapshot: Snapshot) => {
	await network.provider.send('evm_revert', [snapshot.initial]);
	return makeSnapshot(snapshot);
};

export const initiateSnapshot = (): Snapshot => ({
	initial: '0x0',
});

export function prepareSendBulkMailWithTokenArguments(
	args: Parameters<YlideMailerV9['functions']['sendBulkMail(uint256,uint256,uint256[],bytes[],bytes)']>,
	userInfos: YlidePay.TokenInfoStruct[],
) {
	const result = [...args] as any;
	result[2] = result[2].map((recipient: BigNumberish, i: number) => {
		if (userInfos[i]) {
			userInfos[i].recipient = recipient;
			return userInfos[i];
		}
		return {
			recipient,
			amountOrTokenId: 0,
			sendTo: ethers.constants.AddressZero,
			token: ethers.constants.AddressZero,
			tokenType: 0,
			transferType: 0,
		};
	});
	return result as unknown as Parameters<YlidePay['functions']['sendBulkMailWithToken']>;
}

export function prepareAddMailRecipientsWithTokenArguments(
	args: Parameters<
		YlideMailerV9['functions']['addMailRecipients(uint256,uint256,uint256,uint16,uint16,uint256[],bytes[])']
	>,
	userInfos: YlidePay.TokenInfoStruct[],
) {
	const result = [...args] as any;
	result[5] = result[5].map((recipient: BigNumberish, i: number) => {
		if (userInfos[i]) {
			userInfos[i].recipient = recipient;
			return userInfos[i];
		}
		return {
			recipient,
			amountOrTokenId: 0,
			sendTo: ethers.constants.AddressZero,
			token: ethers.constants.AddressZero,
			tokenType: 0,
			transferType: 0,
		};
	});
	return result as Parameters<YlidePay['functions']['addMailRecipientsWithToken']>;
}
