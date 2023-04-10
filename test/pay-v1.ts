import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { expect } from 'chai';
import { ethers, network } from 'hardhat';
import { before, describe, it } from 'mocha';
import { AddMailRecipientsTypes, SendBulkMailTypes } from '../scripts/constants';
import { backToSnapshot, currentTimestamp, initiateSnapshot, toWei } from '../scripts/utils';
import { MockERC20, MockERC721, YlidePayV1 } from '../typechain-types';
import { YlideMailerV9 } from '../typechain-types/contracts/YlideMailerV9';

describe('Token attachment', () => {
	let token1: MockERC20;
	let token2: MockERC20;
	let nft1: MockERC721;
	let nft2: MockERC721;
	let ylideMailer: YlideMailerV9;
	let ylidePay: YlidePayV1;
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
		ylidePay = (await ethers
			.getContractFactory('YlidePayV1', owner)
			.then(f => f.deploy(ylideMailer.address))) as YlidePayV1;
		token1 = (await ethers.getContractFactory('MockERC20').then(f => f.deploy('token1', 'token1'))) as MockERC20;
		token2 = (await ethers.getContractFactory('MockERC20').then(f => f.deploy('token2', 'token2'))) as MockERC20;
		nft1 = (await ethers.getContractFactory('MockERC721').then(f => f.deploy('nft1', 'nft1'))) as MockERC721;
		nft2 = (await ethers.getContractFactory('MockERC721').then(f => f.deploy('nft2', 'nft2'))) as MockERC721;

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
		await ylideMailer.connect(owner).setIsYlideTokenAttachment([ylidePay.address], [true]);
	});

	it('Owner can set ylideMailer in YlidePay', async () => {
		await expect(ylidePay.connect(user1).setYlideMailer(ethers.Wallet.createRandom().address)).to.be.reverted;
		await ylidePay.connect(owner).setYlideMailer(ylideMailer.address);
		expect(await ylidePay.ylideMailer()).equal(ylideMailer.address);
	});

	it('It directly transfers ERC20 type tokens using sendBulkMail', async () => {
		await backToSnapshot(snapshot);

		await token1.connect(user1).mint(toWei(1000));
		await token2.connect(user1).mint(toWei(1000));
		await token1.connect(user1).approve(ylidePay.address, toWei(300));

		const deadline = await currentTimestamp().then(t => t + 1000);
		const nonce1 = await ylideMailer.nonces(user1.address);
		const signature1 = await user1._signTypedData(domain, SendBulkMailTypes, {
			feedId,
			uniqueId,
			nonce: nonce1,
			deadline,
			recipients,
			keys: ethers.utils.concat(keys),
			content,
			contractAddress: ylidePay.address,
			contractType: 1,
		});

		await ylidePay
			.connect(user1)
			.sendBulkMailWithToken(
				getSendBulMailArgs(),
				{ signature: signature1, sender: user1.address, nonce: nonce1, deadline },
				[
					{
						amountOrTokenId: toWei(300),
						recipient: user2.address,
						token: token1.address,
						tokenType: 0,
					},
					{
						amountOrTokenId: 0,
						recipient: ethers.constants.AddressZero,
						token: ethers.constants.AddressZero,
						tokenType: 0,
					},
				],
			);
		expect(await token1.balanceOf(user1.address)).equal(toWei(700));
		expect(await token1.balanceOf(user2.address)).equal(toWei(300));

		const nonce2 = await ylideMailer.nonces(user1.address);

		const signature2 = await user1._signTypedData(domain, SendBulkMailTypes, {
			feedId,
			uniqueId,
			nonce: nonce2,
			deadline,
			recipients,
			keys: ethers.utils.concat(keys),
			content,
			contractAddress: ylidePay.address,
			contractType: 1,
		});

		await token1.connect(user1).approve(ylidePay.address, toWei(200));
		await token2.connect(user1).approve(ylidePay.address, toWei(100));
		await ylidePay
			.connect(user1)
			.sendBulkMailWithToken(
				getSendBulMailArgs(),
				{ signature: signature2, sender: user1.address, nonce: nonce2, deadline },
				[
					{
						amountOrTokenId: toWei(200),
						recipient: user2.address,
						token: token1.address,
						tokenType: 0,
					},
					{
						amountOrTokenId: toWei(100),
						recipient: owner.address,
						token: token2.address,
						tokenType: 0,
					},
				],
			);
		expect(await token1.balanceOf(user1.address)).equal(toWei(500));
		expect(await token1.balanceOf(user2.address)).equal(toWei(500));
		expect(await token1.balanceOf(owner.address)).equal(toWei(0));

		expect(await token2.balanceOf(user1.address)).equal(toWei(900));
		expect(await token2.balanceOf(user2.address)).equal(0);
		expect(await token2.balanceOf(owner.address)).equal(toWei(100));
	});

	it('It directly transfers ERC721 type tokens using sendBulkMail', async () => {
		await backToSnapshot(snapshot);

		await nft1.connect(user1).mint(123);
		await nft1.connect(user1).mint(456);
		await nft2.connect(user1).mint(789);
		await nft1.connect(user1).approve(ylidePay.address, 123);

		const deadline = await currentTimestamp().then(t => t + 1000);
		const nonce1 = await ylideMailer.nonces(user1.address);
		const signature1 = await user1._signTypedData(domain, SendBulkMailTypes, {
			feedId,
			uniqueId,
			nonce: nonce1,
			deadline,
			recipients,
			keys: ethers.utils.concat(keys),
			content,
			contractAddress: ylidePay.address,
			contractType: 1,
		});

		await ylidePay
			.connect(user1)
			.sendBulkMailWithToken(
				getSendBulMailArgs(),
				{ signature: signature1, sender: user1.address, nonce: nonce1, deadline },
				[
					{
						amountOrTokenId: 123,
						recipient: user2.address,
						token: nft1.address,
						tokenType: 1,
					},
				],
			);
		expect(await nft1.balanceOf(user1.address)).equal(1);
		expect(await nft1.balanceOf(user2.address)).equal(1);
		expect(await nft1.ownerOf(123)).equal(user2.address);
		expect(await nft1.ownerOf(456)).equal(user1.address);

		const nonce2 = await ylideMailer.nonces(user1.address);
		const signature2 = await user1._signTypedData(domain, SendBulkMailTypes, {
			feedId,
			uniqueId,
			nonce: nonce2,
			deadline,
			recipients,
			keys: ethers.utils.concat(keys),
			content,
			contractAddress: ylidePay.address,
			contractType: 1,
		});

		await nft1.connect(user1).approve(ylidePay.address, 456);
		await nft2.connect(user1).approve(ylidePay.address, 789);
		await ylidePay
			.connect(user1)
			.sendBulkMailWithToken(
				getSendBulMailArgs(),
				{ signature: signature2, sender: user1.address, nonce: nonce2, deadline },
				[
					{
						amountOrTokenId: 456,
						recipient: user2.address,
						token: nft1.address,
						tokenType: 0,
					},
					{
						amountOrTokenId: 789,
						recipient: owner.address,
						token: nft2.address,
						tokenType: 0,
					},
				],
			);
		expect(await nft1.balanceOf(user1.address)).equal(0);
		expect(await nft1.balanceOf(user2.address)).equal(2);
		expect(await nft1.balanceOf(owner.address)).equal(0);

		expect(await nft2.balanceOf(user1.address)).equal(0);
		expect(await nft2.balanceOf(user2.address)).equal(0);
		expect(await nft2.balanceOf(owner.address)).equal(1);

		expect(await nft1.ownerOf(456)).equal(user2.address);
		expect(await nft2.ownerOf(789)).equal(owner.address);
	});

	it('It directly transfers ERC20 and ERC721 type tokens using sendBulkMail', async () => {
		await backToSnapshot(snapshot);

		await token1.connect(user1).mint(toWei(1000));
		await nft1.connect(user1).mint(123);

		await token1.connect(user1).approve(ylidePay.address, toWei(300));
		await nft1.connect(user1).approve(ylidePay.address, 123);

		const deadline = await currentTimestamp().then(t => t + 1000);
		const nonce1 = await ylideMailer.nonces(user1.address);
		const signature1 = await user1._signTypedData(domain, SendBulkMailTypes, {
			feedId,
			uniqueId,
			nonce: nonce1,
			deadline,
			recipients,
			keys: ethers.utils.concat(keys),
			content,
			contractAddress: ylidePay.address,
			contractType: 1,
		});

		await ylidePay
			.connect(user1)
			.sendBulkMailWithToken(
				getSendBulMailArgs(),
				{ signature: signature1, sender: user1.address, nonce: nonce1, deadline },
				[
					{
						amountOrTokenId: 123,
						recipient: user2.address,
						token: nft1.address,
						tokenType: 1,
					},
					{
						amountOrTokenId: toWei(300),
						recipient: owner.address,
						token: token1.address,
						tokenType: 0,
					},
				],
			);
		expect(await nft1.balanceOf(user1.address)).equal(0);
		expect(await nft1.balanceOf(user2.address)).equal(1);
		expect(await nft1.balanceOf(owner.address)).equal(0);
		expect(await nft1.ownerOf(123)).equal(user2.address);

		expect(await token1.balanceOf(user1.address)).equal(toWei(700));
		expect(await token1.balanceOf(user2.address)).equal(0);
		expect(await token1.balanceOf(owner.address)).equal(toWei(300));
	});

	it('It directly transfers ERC20 type tokens using addMailRecipientsWithToken', async () => {
		await backToSnapshot(snapshot);

		await token1.connect(user1).mint(toWei(1000));
		await token1.connect(user1).approve(ylidePay.address, toWei(300));

		const deadline = await currentTimestamp().then(t => t + 1000);
		const nonce1 = await ylideMailer.nonces(user1.address);
		const signature1 = await user1._signTypedData(domain, AddMailRecipientsTypes, {
			feedId,
			uniqueId,
			firstBlockNumber,
			nonce: nonce1,
			deadline,
			partsCount,
			blockCountLock,
			recipients,
			keys: ethers.utils.concat(keys),
			contractAddress: ylidePay.address,
			contractType: 1,
		});

		await ylidePay
			.connect(user1)
			.addMailRecipientsWithToken(
				getAddMailRecipientsArgs(),
				{ signature: signature1, sender: user1.address, nonce: nonce1, deadline },
				[
					{
						amountOrTokenId: toWei(300),
						recipient: user2.address,
						token: token1.address,
						tokenType: 0,
					},
				],
			);
		expect(await token1.balanceOf(user1.address)).equal(toWei(700));
		expect(await token1.balanceOf(user2.address)).equal(toWei(300));

		await token1.connect(user1).approve(ylidePay.address, toWei(200));

		const nonce2 = await ylideMailer.nonces(user1.address);
		const signature2 = await user1._signTypedData(domain, AddMailRecipientsTypes, {
			feedId,
			uniqueId,
			firstBlockNumber,
			nonce: nonce2,
			deadline,
			partsCount,
			blockCountLock,
			recipients,
			keys: ethers.utils.concat(keys),
			contractAddress: ylidePay.address,
			contractType: 1,
		});
		await ylidePay
			.connect(user1)
			.addMailRecipientsWithToken(
				getAddMailRecipientsArgs(),
				{ signature: signature2, sender: user1.address, nonce: nonce2, deadline },
				[
					{
						amountOrTokenId: toWei(120),
						recipient: user2.address,
						token: token1.address,
						tokenType: 0,
					},
					{
						amountOrTokenId: toWei(80),
						recipient: owner.address,
						token: token1.address,
						tokenType: 0,
					},
				],
			);
		expect(await token1.balanceOf(user1.address)).equal(toWei(500));
		expect(await token1.balanceOf(user2.address)).equal(toWei(420));
		expect(await token1.balanceOf(owner.address)).equal(toWei(80));
	});

	it('It directly transfers ERC721 type tokens using addMailRecipientsWithToken', async () => {
		await backToSnapshot(snapshot);

		await nft1.connect(user1).mint(123);
		await nft1.connect(user1).mint(456);
		await nft1.connect(user1).mint(789);
		await nft1.connect(user1).approve(ylidePay.address, 123);

		const deadline = await currentTimestamp().then(t => t + 1000);
		const nonce1 = await ylideMailer.nonces(user1.address);
		const signature1 = await user1._signTypedData(domain, AddMailRecipientsTypes, {
			feedId,
			uniqueId,
			firstBlockNumber,
			nonce: nonce1,
			deadline,
			partsCount,
			blockCountLock,
			recipients,
			keys: ethers.utils.concat(keys),
			contractAddress: ylidePay.address,
			contractType: 1,
		});

		await ylidePay
			.connect(user1)
			.addMailRecipientsWithToken(
				getAddMailRecipientsArgs(),
				{ signature: signature1, sender: user1.address, nonce: nonce1, deadline },
				[
					{
						amountOrTokenId: 123,
						recipient: user2.address,
						token: nft1.address,
						tokenType: 1,
					},
				],
			);
		expect(await nft1.balanceOf(user1.address)).equal(2);
		expect(await nft1.balanceOf(user2.address)).equal(1);
		expect(await nft1.ownerOf(123)).equal(user2.address);
		expect(await nft1.ownerOf(456)).equal(user1.address);

		await nft1.connect(user1).approve(ylidePay.address, 456);
		await nft1.connect(user1).approve(ylidePay.address, 789);

		const nonce2 = await ylideMailer.nonces(user1.address);
		const signature2 = await user1._signTypedData(domain, AddMailRecipientsTypes, {
			feedId,
			uniqueId,
			firstBlockNumber,
			nonce: nonce2,
			deadline,
			partsCount,
			blockCountLock,
			recipients,
			keys: ethers.utils.concat(keys),
			contractAddress: ylidePay.address,
			contractType: 1,
		});
		await ylidePay
			.connect(user1)
			.addMailRecipientsWithToken(
				getAddMailRecipientsArgs(),
				{ signature: signature2, sender: user1.address, nonce: nonce2, deadline },
				[
					{
						amountOrTokenId: 456,
						recipient: user2.address,
						token: nft1.address,
						tokenType: 0,
					},
					{
						amountOrTokenId: 789,
						recipient: owner.address,
						token: nft1.address,
						tokenType: 0,
					},
				],
			);
		expect(await nft1.balanceOf(user1.address)).equal(0);
		expect(await nft1.balanceOf(user2.address)).equal(2);
		expect(await nft1.balanceOf(owner.address)).equal(1);
		expect(await nft1.ownerOf(456)).equal(user2.address);
		expect(await nft1.ownerOf(789)).equal(owner.address);
	});

	it('It directly transfers ERC20 and ERC721 type tokens using addMailRecipientsWithToken', async () => {
		await backToSnapshot(snapshot);

		await token1.connect(user1).mint(toWei(1000));
		await nft1.connect(user1).mint(123);

		await token1.connect(user1).approve(ylidePay.address, toWei(300));
		await nft1.connect(user1).approve(ylidePay.address, 123);

		const deadline = await currentTimestamp().then(t => t + 1000);
		const nonce1 = await ylideMailer.nonces(user1.address);
		const signature1 = await user1._signTypedData(domain, AddMailRecipientsTypes, {
			feedId,
			uniqueId,
			firstBlockNumber,
			nonce: nonce1,
			deadline,
			partsCount,
			blockCountLock,
			recipients,
			keys: ethers.utils.concat(keys),
			contractAddress: ylidePay.address,
			contractType: 1,
		});
		await ylidePay
			.connect(user1)
			.addMailRecipientsWithToken(
				getAddMailRecipientsArgs(),
				{ signature: signature1, sender: user1.address, nonce: nonce1, deadline },
				[
					{
						amountOrTokenId: 123,
						recipient: user2.address,
						token: nft1.address,
						tokenType: 0,
					},
					{
						amountOrTokenId: toWei(300),
						recipient: owner.address,
						token: token1.address,
						tokenType: 0,
					},
				],
			);
		expect(await nft1.balanceOf(user1.address)).equal(0);
		expect(await nft1.balanceOf(user2.address)).equal(1);
		expect(await nft1.balanceOf(owner.address)).equal(0);
		expect(await nft1.ownerOf(123)).equal(user2.address);

		expect(await token1.balanceOf(user1.address)).equal(toWei(700));
		expect(await token1.balanceOf(user2.address)).equal(0);
		expect(await token1.balanceOf(owner.address)).equal(toWei(300));
	});
});
