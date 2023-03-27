import { ethers, network } from 'hardhat';
import { YlideMailerV9, YlidePayV1, YlideStreamSablierV1 } from 'typechain-types';
import { IYlideTokenAttachment } from 'typechain-types/contracts/YlidePayV1';
import { Snapshot } from './types';

export function toWei(amount: string | number) {
	return ethers.utils.parseUnits(String(amount), 18);
}

export function toWei6(amount: string | number) {
	return ethers.utils.parseUnits(String(amount), 6);
}

export const currentTimestamp = () =>
	ethers.provider.getBlock(ethers.provider.getBlockNumber()).then(block => block.timestamp);

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
	infos: IYlideTokenAttachment.TransferInfoStruct[],
): Parameters<YlidePayV1['functions']['sendBulkMailWithToken']>;
export function prepareSendBulkMailWithTokenArguments(
	args: Parameters<YlideMailerV9['functions']['sendBulkMail(uint256,uint256,uint256[],bytes[],bytes)']>,
	infos: YlideStreamSablierV1.StreamInfoStruct[],
): Parameters<YlideStreamSablierV1['functions']['sendBulkMailWithToken']>;
export function prepareSendBulkMailWithTokenArguments(
	args: Parameters<YlideMailerV9['functions']['sendBulkMail(uint256,uint256,uint256[],bytes[],bytes)']>,
	infos: any,
) {
	const result = [...args] as any;
	result[5] = infos;
	return result;
}

export function prepareAddMailRecipientsWithTokenArguments(
	args: Parameters<
		YlideMailerV9['functions']['addMailRecipients(uint256,uint256,uint256,uint16,uint16,uint256[],bytes[])']
	>,
	infos: IYlideTokenAttachment.TransferInfoStruct[],
): Parameters<YlidePayV1['functions']['addMailRecipientsWithToken']>;
export function prepareAddMailRecipientsWithTokenArguments(
	args: Parameters<
		YlideMailerV9['functions']['addMailRecipients(uint256,uint256,uint256,uint16,uint16,uint256[],bytes[])']
	>,
	infos: YlideStreamSablierV1.StreamInfoStruct[],
): Parameters<YlideStreamSablierV1['functions']['addMailRecipientsWithToken']>;
export function prepareAddMailRecipientsWithTokenArguments(
	args: Parameters<
		YlideMailerV9['functions']['addMailRecipients(uint256,uint256,uint256,uint16,uint16,uint256[],bytes[])']
	>,
	userInfos: any,
) {
	const result = [...args] as any;
	result[7] = userInfos;
	return result;
}
