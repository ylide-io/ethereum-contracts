import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
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
	let mockSafe2: MockSafe;
	let mockSafe3: MockSafe;
	let owner: SignerWithAddress;
	let user1: SignerWithAddress;
	let user2: SignerWithAddress;
	let user3: SignerWithAddress;

	let domain: {
		name: string;
		version: string;
		chainId: number;
		verifyingContract: string;
	};

	const snapshot = initiateSnapshot();

	let feedId: string;
	const uniqueId = 123;
	const keys = [new Uint8Array([1, 2, 3, 4, 5, 6]), new Uint8Array([6, 5, 4, 3, 2, 1])];
	const content = new Uint8Array([8, 7, 8, 7, 8, 7]);

	let firstBlockNumber: number;
	let partsCount = 4;
	let blockCountLock = 20;

	const getSendBulMailArgs = (recipients: BigNumber[]) => ({
		feedId,
		uniqueId,
		recipients,
		keys,
		content,
	});

	const getAddMailRecipientsArgs = (r: BigNumber[]) => ({
		feedId,
		uniqueId,
		recipients: r,
		keys,
		partsCount,
		blockCountLock,
		firstBlockNumber,
	});

	before(async () => {
		[owner, user1, user2, user3] = await ethers.getSigners();
		ylideMailer = (await ethers.getContractFactory('YlideMailerV9', owner).then(f => f.deploy())) as YlideMailerV9;
		ylideSafe = (await ethers
			.getContractFactory('YlideSafeV1', owner)
			.then(f => f.deploy(ylideMailer.address))) as YlideSafeV1;

		mockSafe = (await ethers.getContractFactory('MockSafe', owner).then(f => f.deploy())) as MockSafe;
		mockSafe2 = (await ethers.getContractFactory('MockSafe', owner).then(f => f.deploy())) as MockSafe;
		mockSafe3 = (await ethers.getContractFactory('MockSafe', owner).then(f => f.deploy())) as MockSafe;

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

	it('Reverts on _validate()', async () => {
		await backToSnapshot(snapshot);

		const signature =
			'0xf677181dfe0e10c6ea91d012f09c7f6da7477ec75489a2322fbbfe9d878224b2314121c86229a7a77a2a0a5f3b72fe4668ea8183938154374a8cde9aeff1a6d41b';

		await expect(
			ylideSafe.connect(user2).addMailRecipients(
				getAddMailRecipientsArgs([BigNumber.from(user1.address)]),
				{
					signature,
					sender: user1.address,
					nonce: 0,
					deadline: 123,
				},
				{ safeSender: mockSafe.address, safeRecipients: [mockSafe2.address] },
			),
		).to.be.revertedWithCustomError(ylideSafe, 'InvalidSender');

		await expect(
			ylideSafe.connect(user2).sendBulkMail(
				getSendBulMailArgs([BigNumber.from(user1.address), BigNumber.from(owner.address)]),
				{
					signature,
					sender: user2.address,
					nonce: 0,
					deadline: 123,
				},
				{ safeSender: mockSafe.address, safeRecipients: [mockSafe2.address] },
			),
		).to.be.revertedWithCustomError(ylideSafe, 'InvalidArguments');
		await expect(
			ylideSafe.connect(user2).addMailRecipients(
				getAddMailRecipientsArgs([BigNumber.from(user1.address), BigNumber.from(owner.address)]),
				{
					signature,
					sender: user2.address,
					nonce: 0,
					deadline: 123,
				},
				{ safeSender: mockSafe.address, safeRecipients: [mockSafe2.address] },
			),
		).to.be.revertedWithCustomError(ylideSafe, 'InvalidArguments');
	});

	it('Owner of safe can send message using sendBulkMail', async () => {
		await backToSnapshot(snapshot);

		const deadline = await currentTimestamp().then(t => t + 1000);
		const nonce = await ylideMailer.nonces(user1.address);
		const recipients = [BigNumber.from(user2.address), BigNumber.from(owner.address)];
		const safeRecipients = [mockSafe2.address, ethers.constants.AddressZero];
		const signature = await user1._signTypedData(domain, SendBulkMailTypes, {
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

		await ylideSafe.connect(user1).sendBulkMail(
			getSendBulMailArgs(recipients),
			{
				signature,
				sender: user1.address,
				nonce,
				deadline,
			},
			{ safeSender: mockSafe.address, safeRecipients },
		);

		const mailEvents = await ylideMailer.queryFilter(ylideMailer.filters.MailPush(null, feedId));

		expect(mailEvents.length).equal(2);
		for (const event of mailEvents) {
			expect(event.args.supplement.contractAddress).equal(ylideSafe.address);
			expect(event.args.supplement.contractType).equal(ContractType.SAFE);
		}

		const safeEvents = await ylideSafe.queryFilter(ylideSafe.filters.SafeMails(mailEvents[0].args.contentId));
		expect(safeEvents.length).equal(1);
		expect(safeEvents[0].args.contentId).equal(mailEvents[0].args.contentId);
		expect(safeEvents[0].args.safeSender).equal(mockSafe.address);
		expect(safeEvents[0].args.safeRecipients).deep.equal(safeRecipients);
	});

	it('Owner of safe can send message using addMailRecipients', async () => {
		await backToSnapshot(snapshot);

		const deadline = await currentTimestamp().then(t => t + 1000);
		const nonce = await ylideMailer.nonces(user1.address);
		const recipients = [BigNumber.from(user2.address), BigNumber.from(user3.address)];
		const safeRecipients = [mockSafe2.address, mockSafe3.address];
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
			contractAddress: ylideSafe.address,
			contractType: ContractType.SAFE,
		});

		await ylideSafe.connect(user1).addMailRecipients(
			getAddMailRecipientsArgs(recipients),
			{
				signature,
				sender: user1.address,
				nonce,
				deadline,
			},
			{ safeSender: mockSafe.address, safeRecipients },
		);

		const mailEvents = await ylideMailer.queryFilter(ylideMailer.filters.MailPush(null, feedId));

		expect(mailEvents.length).equal(2);
		for (const event of mailEvents) {
			expect(event.args.supplement.contractAddress).equal(ylideSafe.address);
			expect(event.args.supplement.contractType).equal(ContractType.SAFE);
		}

		const safeEvents = await ylideSafe.queryFilter(ylideSafe.filters.SafeMails(mailEvents[0].args.contentId));
		expect(safeEvents.length).equal(1);
		expect(safeEvents[0].args.contentId).equal(mailEvents[0].args.contentId);
		expect(safeEvents[0].args.safeSender).equal(mockSafe.address);
		expect(safeEvents[0].args.safeRecipients).deep.equal(safeRecipients);
	});

	it('Not owner of any safe can send message to some user with Safe', async () => {
		await backToSnapshot(snapshot);

		const deadline = await currentTimestamp().then(t => t + 1000);
		const nonce = await ylideMailer.nonces(user1.address);
		const recipients = [BigNumber.from(user2.address), BigNumber.from(user3.address)];
		const safeRecipients = [mockSafe2.address, ethers.constants.AddressZero];
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
			contractAddress: ylideSafe.address,
			contractType: ContractType.SAFE,
		});

		await ylideSafe.connect(user1).addMailRecipients(
			getAddMailRecipientsArgs(recipients),
			{
				signature,
				sender: user1.address,
				nonce,
				deadline,
			},
			{ safeSender: ethers.constants.AddressZero, safeRecipients },
		);

		const mailEvents = await ylideMailer.queryFilter(ylideMailer.filters.MailPush(null, feedId));

		expect(mailEvents.length).equal(2);
		for (const event of mailEvents) {
			expect(event.args.supplement.contractAddress).equal(ylideSafe.address);
			expect(event.args.supplement.contractType).equal(ContractType.SAFE);
		}

		const safeEvents = await ylideSafe.queryFilter(ylideSafe.filters.SafeMails(mailEvents[0].args.contentId));
		expect(safeEvents.length).equal(1);
		expect(safeEvents[0].args.contentId).equal(mailEvents[0].args.contentId);
		expect(safeEvents[0].args.safeSender).equal(ethers.constants.AddressZero);
		expect(safeEvents[0].args.safeRecipients).deep.equal(safeRecipients);
	});
});
