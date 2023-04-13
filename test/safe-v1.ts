import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { expect } from 'chai';
import { ethers, network } from 'hardhat';
import { before, describe, it } from 'mocha';
import { AddMailRecipientsTypes, ContractType, SendBulkMailTypes } from '../scripts/constants';
import { backToSnapshot, currentTimestamp, initiateSnapshot } from '../scripts/utils';
import { MockSafe, YlideSafeV1 } from '../typechain-types';
import { YlideMailerV9 } from '../typechain-types/contracts/YlideMailerV9';

describe('Ylide Safe', () => {
	let ylideMailer: YlideMailerV9;
	let ylideSafe: YlideSafeV1;
	let mockSafe: MockSafe;
	let owner: SignerWithAddress;
	let user1: SignerWithAddress;
	let user2: SignerWithAddress;

	let domain: {
		name: string;
		version: string;
		chainId: number;
		verifyingContract: string;
	};

	const snapshot = initiateSnapshot();

	let feedId: string;
	const uniqueId = 123;
	const recipients = [1, 2];
	const keys = [new Uint8Array([1, 2, 3, 4, 5, 6]), new Uint8Array([6, 5, 4, 3, 2, 1])];
	const content = new Uint8Array([8, 7, 8, 7, 8, 7]);

	let firstBlockNumber: number;
	let partsCount = 4;
	let blockCountLock = 20;

	const getSendBulMailArgs = () => ({
		feedId,
		uniqueId,
		recipients,
		keys,
		content,
	});

	const getAddMailRecipientsArgs = () => ({
		feedId,
		uniqueId,
		recipients,
		keys,
		partsCount,
		blockCountLock,
		firstBlockNumber,
	});

	before(async () => {
		[owner, user1, user2] = await ethers.getSigners();
		ylideMailer = (await ethers.getContractFactory('YlideMailerV9', owner).then(f => f.deploy())) as YlideMailerV9;
		ylideSafe = (await ethers
			.getContractFactory('YlideSafeV1', owner)
			.then(f => f.deploy(ylideMailer.address))) as YlideSafeV1;

		mockSafe = (await ethers.getContractFactory('MockSafe', owner).then(f => f.deploy())) as MockSafe;

		await mockSafe.setOwners([user1.address], [true]);

		const tx = await ylideMailer.createMailingFeed('768768768768121341');
		const receipt = await tx.wait();
		feedId = String(receipt.events?.[0].args?.[0] || 0);
		domain = {
			name: 'YlideMailerV9',
			version: '9',
			chainId: network.config.chainId!,
			verifyingContract: ylideMailer.address,
		};
		firstBlockNumber = await ethers.provider.getBlockNumber();
		await ylideMailer.connect(owner).setIsYlide([ylideSafe.address], [true]);
	});

	it('Owner can set ylideMailer in YlideSafe', async () => {
		await expect(ylideSafe.connect(user1).setYlideMailer(ethers.Wallet.createRandom().address)).to.be.reverted;
		await ylideSafe.connect(owner).setYlideMailer(ylideMailer.address);
		expect(await ylideSafe.ylideMailer()).equal(ylideMailer.address);
	});

	it('Not owner of safe cannot send message', async () => {
		await backToSnapshot(snapshot);

		const deadline = await currentTimestamp().then(t => t + 1000);
		const nonce = await ylideMailer.nonces(user2.address);
		const signature = await user2._signTypedData(domain, SendBulkMailTypes, {
			feedId,
			uniqueId,
			nonce,
			deadline,
			recipients,
			keys: ethers.utils.concat(keys),
			content,
			contractAddress: ylideSafe.address,
			contractType: ContractType.SAFE,
		});

		expect(await mockSafe.isOwner(user2.address)).to.be.false;

		await expect(
			ylideSafe.connect(user2).sendBulkMail(
				getSendBulMailArgs(),
				{
					signature,
					sender: user2.address,
					nonce,
					deadline,
				},
				mockSafe.address,
			),
		).to.be.revertedWithCustomError(ylideSafe, 'NotSafeOwner');

		const signature2 = await user2._signTypedData(domain, AddMailRecipientsTypes, {
			feedId,
			uniqueId,
			firstBlockNumber,
			nonce,
			deadline,
			partsCount,
			blockCountLock,
			recipients,
			keys: ethers.utils.concat(keys),
			contractAddress: ylideSafe.address,
			contractType: ContractType.SAFE,
		});

		await expect(
			ylideSafe.connect(user2).addMailRecipients(
				getAddMailRecipientsArgs(),
				{
					signature: signature2,
					sender: user2.address,
					nonce,
					deadline,
				},
				mockSafe.address,
			),
		).to.be.revertedWithCustomError(ylideSafe, 'NotSafeOwner');
	});

	it('Owner of safe can send message using sendBulkMail', async () => {
		await backToSnapshot(snapshot);

		const deadline = await currentTimestamp().then(t => t + 1000);
		const nonce = await ylideMailer.nonces(user1.address);
		const signature = await user1._signTypedData(domain, SendBulkMailTypes, {
			feedId,
			uniqueId,
			nonce,
			deadline,
			recipients,
			keys: ethers.utils.concat(keys),
			content,
			contractAddress: mockSafe.address,
			contractType: ContractType.SAFE,
		});

		expect(await mockSafe.isOwner(user1.address)).to.be.true;

		await ylideSafe.connect(user1).sendBulkMail(
			getSendBulMailArgs(),
			{
				signature,
				sender: user1.address,
				nonce,
				deadline,
			},
			mockSafe.address,
		);

		const events = await ylideMailer.queryFilter(ylideMailer.filters.MailPush(null, feedId));

		expect(events.length).equal(2);
		for (const event of events) {
			expect(event.args.supplement.contractAddress).equal(mockSafe.address);
			expect(event.args.supplement.contractType).equal(ContractType.SAFE);
		}
	});

	it('Owner of safe can send message using addMailRecipients', async () => {
		await backToSnapshot(snapshot);

		const deadline = await currentTimestamp().then(t => t + 1000);
		const nonce = await ylideMailer.nonces(user1.address);
		const signature = await user1._signTypedData(domain, AddMailRecipientsTypes, {
			feedId,
			uniqueId,
			firstBlockNumber,
			nonce,
			deadline,
			partsCount,
			blockCountLock,
			recipients,
			keys: ethers.utils.concat(keys),
			contractAddress: mockSafe.address,
			contractType: ContractType.SAFE,
		});

		expect(await mockSafe.isOwner(user1.address)).to.be.true;

		await ylideSafe.connect(user1).addMailRecipients(
			getAddMailRecipientsArgs(),
			{
				signature,
				sender: user1.address,
				nonce,
				deadline,
			},
			mockSafe.address,
		);

		const events = await ylideMailer.queryFilter(ylideMailer.filters.MailPush(null, feedId));

		expect(events.length).equal(2);
		for (const event of events) {
			expect(event.args.supplement.contractAddress).equal(mockSafe.address);
			expect(event.args.supplement.contractType).equal(ContractType.SAFE);
		}
	});
});
