import { ethers, network } from 'hardhat';
import { Snapshot } from './types';
import { Contract } from 'ethers';
import { ConfigFacet } from '../typechain-types';

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

export function getSelectors(contract: Contract) {
	return Object.keys(contract.interface.functions).reduce((acc, val) => {
		if (val !== 'init(bytes)') {
			acc.push(contract.interface.getSighash(val));
		}
		return acc;
	}, [] as string[]);
}

export async function mine(sleepDuration?: number) {
	if (sleepDuration) {
		await ethers.provider.send('evm_increaseTime', [sleepDuration]);
	}

	return ethers.provider.send('evm_mine', []);
}

export const whitelistedOneself = async (contract: ConfigFacet, userAddress: string) => {
	const [r1, r2] = await Promise.all([
		contract.recipientToWhitelistedSender(userAddress, userAddress),
		contract.recipientToWhitelistedSender(
			ethers.utils.sha256(ethers.utils.defaultAbiCoder.encode(['address'], [userAddress])),
			userAddress,
		),
	]);
	return r1 && r2;
};
