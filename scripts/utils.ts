import { ethers, network } from 'hardhat';
import { Snapshot } from './types';
import crypto from 'crypto';

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
