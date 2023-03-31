import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers, network } from 'hardhat';
import { describe } from 'mocha';
import {
	addMailRecipientsSelector,
	AddMailRecipientsTypes,
	sendBulkMailSelector,
	SendBulkMailTypes,
} from '../scripts/constants';
import { currentTimestamp } from '../scripts/utils';
import { YlideMailerV9 } from '../typechain-types';

describe('MailerV9 EIP712 signature', () => {
	let ylideMailer: YlideMailerV9;
	let owner: SignerWithAddress;
	let user1: SignerWithAddress;
	let user2: SignerWithAddress;

	let feedId: string;
	const uniqueId = 123;
	const recipients = [1, 2];
	const keys = [new Uint8Array([1, 2, 3, 4, 5, 6]), new Uint8Array([6, 5, 4, 3, 2, 1])];
	const content = new Uint8Array([8, 7, 8, 7, 8, 7]);

	before(async () => {
		[owner, user1, user2] = await ethers.getSigners();
		ylideMailer = (await ethers
			.getContractFactory('YlideMailerV9', owner)
			.then(factory => factory.deploy())) as YlideMailerV9;
		const tx = await ylideMailer.createMailingFeed('768768768768121341');
		const receipt = await tx.wait();
		feedId = String(receipt.events?.[0].args?.[0] || 0);
		await ylideMailer.connect(owner).setIsYlideTokenAttachment([owner.address], [true]);
	});

	it('sendBulkMail with signature', async () => {
		// 'SendBulkMail(uint256 feedId,uint256 uniqueId,uint256 nonce,uint256 deadline,uint256[] recipients,bytes keys,bytes content)';
		const nonce = 100;
		const deadline = await currentTimestamp();
		const domain = {
			name: 'YlideMailerV9',
			version: '9',
			chainId: network.config.chainId,
			verifyingContract: ylideMailer.address,
		};

		const signature = await user1._signTypedData(domain, SendBulkMailTypes, {
			feedId,
			uniqueId,
			nonce,
			deadline,
			recipients,
			keys: ethers.utils.concat(keys),
			content,
		});

		await expect(
			ylideMailer.connect(user1)[sendBulkMailSelector](
				{
					feedId,
					uniqueId,
					recipients,
					keys,
					content,
				},
				{ signature, sender: user1.address, nonce, deadline },
			),
		).to.be.revertedWithCustomError(ylideMailer, 'IsNotYlide');

		await expect(
			ylideMailer.connect(owner)[sendBulkMailSelector](
				{
					feedId,
					uniqueId,
					recipients,
					keys,
					content,
				},
				{ signature, sender: user2.address, nonce, deadline },
			),
		).to.be.revertedWithCustomError(ylideMailer, 'InvalidSignature');

		await expect(
			ylideMailer.connect(owner)[sendBulkMailSelector](
				{
					feedId,
					uniqueId,
					recipients,
					keys,
					content,
				},
				{ signature, sender: user1.address, nonce, deadline },
			),
		).to.be.revertedWithCustomError(ylideMailer, 'InvalidNonce');

		const nonceCorrect = await ylideMailer.nonces(user1.address);

		const signature2 = await user1._signTypedData(domain, SendBulkMailTypes, {
			feedId,
			uniqueId,
			nonce: nonceCorrect,
			deadline,
			recipients,
			keys: ethers.utils.concat(keys),
			content,
		});

		await expect(
			ylideMailer.connect(owner)[sendBulkMailSelector](
				{
					feedId,
					uniqueId,
					recipients,
					keys,
					content,
				},
				{ signature: signature2, sender: user1.address, nonce: nonceCorrect, deadline },
			),
		).to.be.revertedWithCustomError(ylideMailer, 'SignatureExpired');

		const correctDeadline = deadline + 1000;

		const signature3 = await user1._signTypedData(domain, SendBulkMailTypes, {
			feedId,
			uniqueId,
			nonce: nonceCorrect,
			deadline: correctDeadline,
			recipients,
			keys: ethers.utils.concat(keys),
			content,
		});

		await ylideMailer.connect(owner)[sendBulkMailSelector](
			{
				feedId,
				uniqueId,
				recipients,
				keys,
				content,
			},
			{ signature: signature3, sender: user1.address, nonce: nonceCorrect, deadline: correctDeadline },
		);

		expect(await ylideMailer.nonces(user1.address)).to.be.equal(nonceCorrect.add(1));
	});

	it('addMailRecipients with signature', async () => {
		// "AddMailRecipients(uint256 feedId,uint256 uniqueId,uint256 firstBlockNumber,uint256 nonce,uint256 deadline, uint16 partsCount,uint16 blockCountLock,uint256[] recipients,bytes keys)"
		const firstBlockNumber = await ethers.provider.getBlockNumber();
		const partsCount = 2;
		const blockCountLock = 10;
		const nonce = 100;
		const deadline = await currentTimestamp();
		const domain = {
			name: 'YlideMailerV9',
			version: '9',
			chainId: network.config.chainId,
			verifyingContract: ylideMailer.address,
		};

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
		});

		await expect(
			ylideMailer.connect(user1)[addMailRecipientsSelector](
				{
					feedId,
					uniqueId,
					recipients,
					keys,
					partsCount,
					blockCountLock,
					firstBlockNumber,
				},
				{ signature, sender: user1.address, nonce, deadline },
			),
		).to.be.revertedWithCustomError(ylideMailer, 'IsNotYlide');

		await expect(
			ylideMailer.connect(owner)[addMailRecipientsSelector](
				{
					feedId,
					uniqueId,
					recipients,
					keys,
					partsCount,
					blockCountLock,
					firstBlockNumber,
				},
				{ signature, sender: user2.address, nonce, deadline },
			),
		).to.be.revertedWithCustomError(ylideMailer, 'InvalidSignature');

		await expect(
			ylideMailer.connect(owner)[addMailRecipientsSelector](
				{
					feedId,
					uniqueId,
					recipients,
					keys,
					partsCount,
					blockCountLock,
					firstBlockNumber,
				},
				{ signature, sender: user1.address, nonce, deadline },
			),
		).to.be.revertedWithCustomError(ylideMailer, 'InvalidNonce');

		const nonceCorrect = await ylideMailer.nonces(user1.address);

		const signature2 = await user1._signTypedData(domain, AddMailRecipientsTypes, {
			feedId,
			uniqueId,
			firstBlockNumber,
			nonce: nonceCorrect,
			deadline,
			partsCount,
			blockCountLock,
			recipients,
			keys: ethers.utils.concat(keys),
		});

		await expect(
			ylideMailer.connect(owner)[addMailRecipientsSelector](
				{
					feedId,
					uniqueId,
					recipients,
					keys,
					partsCount,
					blockCountLock,
					firstBlockNumber,
				},
				{ signature: signature2, sender: user1.address, nonce: nonceCorrect, deadline },
			),
		).to.be.revertedWithCustomError(ylideMailer, 'SignatureExpired');

		const correctDeadline = deadline + 1000;

		const signature3 = await user1._signTypedData(domain, AddMailRecipientsTypes, {
			feedId,
			uniqueId,
			firstBlockNumber,
			nonce: nonceCorrect,
			deadline: correctDeadline,
			partsCount,
			blockCountLock,
			recipients,
			keys: ethers.utils.concat(keys),
		});

		await ylideMailer.connect(owner)[addMailRecipientsSelector](
			{
				feedId,
				uniqueId,
				recipients,
				keys,
				partsCount,
				blockCountLock,
				firstBlockNumber,
			},
			{ signature: signature3, sender: user1.address, nonce: nonceCorrect, deadline: correctDeadline },
		);

		expect(await ylideMailer.nonces(user1.address)).to.be.equal(nonceCorrect.add(1));
	});
});
