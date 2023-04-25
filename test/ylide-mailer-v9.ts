import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { ethers } from 'hardhat';
import { before, describe } from 'mocha';
import { backToSnapshot, initiateSnapshot } from '../scripts/utils';
import { YlideMailerV9 } from '../typechain-types/contracts/YlideMailerV9';
import { BigNumber } from 'ethers';
import { expect } from 'chai';

describe('Ylide Safe', () => {
	let ylideMailer: YlideMailerV9;
	let owner: SignerWithAddress;
	let user1: SignerWithAddress;
	let user2: SignerWithAddress;
	let user3: SignerWithAddress;

	const snapshot = initiateSnapshot();

	let feedId: string;
	const uniqueId = 123;
	const content = new Uint8Array([8, 7, 8, 7, 8, 7]);

	let firstBlockNumber: number;
	let partsCount = 4;
	let blockCountLock = 20;

	before(async () => {
		[owner, user1, user2, user3] = await ethers.getSigners();
		ylideMailer = (await ethers.getContractFactory('YlideMailerV9', owner).then(f => f.deploy())) as YlideMailerV9;
		const tx = await ylideMailer.createMailingFeed('768768768768121341');
		const receipt = await tx.wait();
		feedId = String(receipt.events?.[0].args?.[0] || 0);
		firstBlockNumber = await ethers.provider.getBlockNumber();
	});

	it('Simple sendBulkMail', async () => {
		await backToSnapshot(snapshot);
		const recKeySups = [
			{ recipient: BigNumber.from(user2.address), key: '0x0102', supplement: '0x' },
			{ recipient: BigNumber.from(owner.address), key: '0x010203', supplement: '0x' },
		];
		await ylideMailer.connect(user1).sendBulkMail(feedId, uniqueId, recKeySups, content);
		const mailEvents = await ylideMailer.queryFilter(ylideMailer.filters.MailPush(null, feedId));

		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user1.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);
		}
	});

	it('Simple addMailRecipients', async () => {
		await backToSnapshot(snapshot);
		const recKeySups = [
			{ recipient: BigNumber.from(user2.address), key: '0x0102', supplement: '0x' },
			{ recipient: BigNumber.from(owner.address), key: '0x010203', supplement: '0x' },
		];
		await ylideMailer
			.connect(user1)
			.addMailRecipients(feedId, uniqueId, recKeySups, firstBlockNumber, partsCount, blockCountLock);
		const mailEvents = await ylideMailer.queryFilter(ylideMailer.filters.MailPush(null, feedId));

		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user1.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);
		}
	});

	it('Safe owner sendBulkMail', async () => {
		await backToSnapshot(snapshot);
		const senderSafeAddress = ethers.Wallet.createRandom().address;
		const user2SafeAddress = ethers.Wallet.createRandom().address;
		const supplementType = ['uint8', 'address', 'address'] as const;
		const supplements = [
			[1, senderSafeAddress, user2SafeAddress] as const,
			[1, senderSafeAddress, ethers.constants.AddressZero] as const,
		];
		const recKeySups = [
			{
				recipient: BigNumber.from(user2.address),
				key: '0x0102',
				supplement: ethers.utils.defaultAbiCoder.encode(supplementType, supplements[0]),
			},
			{
				recipient: BigNumber.from(owner.address),
				key: '0x010203',
				supplement: ethers.utils.defaultAbiCoder.encode(supplementType, supplements[1]),
			},
		];
		await ylideMailer.connect(user1).sendBulkMail(feedId, uniqueId, recKeySups, content);
		const mailEvents = await ylideMailer.queryFilter(ylideMailer.filters.MailPush(null, feedId));

		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user1.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);

			const supplement = ethers.utils.defaultAbiCoder.decode(supplementType, mailEvents[i].args.supplement);
			expect(supplement).deep.equal(supplements[i]);
		}
	});

	it('Not safe owner sendBulkMail to safe owners', async () => {
		await backToSnapshot(snapshot);
		const user2SafeAddress = ethers.Wallet.createRandom().address;
		const supplementType = ['uint8', 'address', 'address'] as const;
		const supplements = [
			[1, ethers.constants.AddressZero, user2SafeAddress] as const,
			[1, ethers.constants.AddressZero, ethers.constants.AddressZero] as const,
		];
		const recKeySups = [
			{
				recipient: BigNumber.from(user2.address),
				key: '0x0102',
				supplement: ethers.utils.defaultAbiCoder.encode(supplementType, supplements[0]),
			},
			{
				recipient: BigNumber.from(owner.address),
				key: '0x010203',
				supplement: ethers.utils.defaultAbiCoder.encode(supplementType, supplements[1]),
			},
		];
		await ylideMailer.connect(user1).sendBulkMail(feedId, uniqueId, recKeySups, content);
		const mailEvents = await ylideMailer.queryFilter(ylideMailer.filters.MailPush(null, feedId));

		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user1.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);

			const supplement = ethers.utils.defaultAbiCoder.decode(supplementType, mailEvents[i].args.supplement);
			expect(supplement).deep.equal(supplements[i]);
		}
	});

	it('Safe owner addMailRecipients', async () => {
		await backToSnapshot(snapshot);
		const senderSafeAddress = ethers.Wallet.createRandom().address;
		const user2SafeAddress = ethers.Wallet.createRandom().address;
		const supplementType = ['uint8', 'address', 'address'] as const;
		const supplements = [
			[1, senderSafeAddress, user2SafeAddress] as const,
			[1, senderSafeAddress, ethers.constants.AddressZero] as const,
		];
		const recKeySups = [
			{
				recipient: BigNumber.from(user2.address),
				key: '0x0102',
				supplement: ethers.utils.defaultAbiCoder.encode(supplementType, supplements[0]),
			},
			{
				recipient: BigNumber.from(owner.address),
				key: '0x010203',
				supplement: ethers.utils.defaultAbiCoder.encode(supplementType, supplements[1]),
			},
		];
		await ylideMailer
			.connect(user1)
			.addMailRecipients(feedId, uniqueId, recKeySups, firstBlockNumber, partsCount, blockCountLock);
		const mailEvents = await ylideMailer.queryFilter(ylideMailer.filters.MailPush(null, feedId));

		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user1.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);

			const supplement = ethers.utils.defaultAbiCoder.decode(supplementType, mailEvents[i].args.supplement);
			expect(supplement).deep.equal(supplements[i]);
		}
	});

	it('Not safe owner sendBulkMail to safe owners', async () => {
		await backToSnapshot(snapshot);
		const user2SafeAddress = ethers.Wallet.createRandom().address;
		const supplementType = ['uint8', 'address', 'address'] as const;
		const supplements = [
			[1, ethers.constants.AddressZero, user2SafeAddress] as const,
			[1, ethers.constants.AddressZero, ethers.constants.AddressZero] as const,
		];
		const recKeySups = [
			{
				recipient: BigNumber.from(user2.address),
				key: '0x0102',
				supplement: ethers.utils.defaultAbiCoder.encode(supplementType, supplements[0]),
			},
			{
				recipient: BigNumber.from(owner.address),
				key: '0x010203',
				supplement: ethers.utils.defaultAbiCoder.encode(supplementType, supplements[1]),
			},
		];
		await ylideMailer
			.connect(user1)
			.addMailRecipients(feedId, uniqueId, recKeySups, firstBlockNumber, partsCount, blockCountLock);
		const mailEvents = await ylideMailer.queryFilter(ylideMailer.filters.MailPush(null, feedId));

		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user1.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);

			const supplement = ethers.utils.defaultAbiCoder.decode(supplementType, mailEvents[i].args.supplement);
			expect(supplement).deep.equal(supplements[i]);
		}
	});
});
