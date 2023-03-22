import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { before, describe, it } from 'mocha';
import { MockERC20, MockERC721, YlideMailerV9, YlidePay } from 'typechain-types';
import {
	backToSnapshot,
	initiateSnapshot,
	makeSnapshot,
	prepareAddMailRecipientsWithTokenArguments,
	prepareSendBulkMailWithTokenArguments,
	toWei,
} from '../scripts/utils';

describe('Token attachment', () => {
	let token1: MockERC20;
	let token2: MockERC20;
	let nft1: MockERC721;
	let nft2: MockERC721;
	let ylideMailer: YlideMailerV9;
	let ylidePay: YlidePay;
	let owner: SignerWithAddress;
	let user1: SignerWithAddress;
	let user2: SignerWithAddress;
	let sendBulkMailArgs: Parameters<
		YlideMailerV9['functions']['sendBulkMail(uint256,uint256,uint256[],bytes[],bytes)']
	>;
	let addMailRecipientsArgs: Parameters<
		YlideMailerV9['functions']['addMailRecipients(uint256,uint256,uint256,uint16,uint16,uint256[],bytes[])']
	>;

	const snapshot = initiateSnapshot();

	before(async () => {
		[owner, user1, user2] = await ethers.getSigners();
		ylideMailer = (await ethers.getContractFactory('YlideMailerV9', owner).then(f => f.deploy())) as YlideMailerV9;
		ylidePay = (await ethers.getContractFactory('YlidePay', owner).then(f => f.deploy())) as YlidePay;
		token1 = (await ethers.getContractFactory('MockERC20').then(f => f.deploy('token1', 'token1'))) as MockERC20;
		token2 = (await ethers.getContractFactory('MockERC20').then(f => f.deploy('token2', 'token2'))) as MockERC20;
		nft1 = (await ethers.getContractFactory('MockERC721').then(f => f.deploy('nft1', 'nft1'))) as MockERC721;
		nft2 = (await ethers.getContractFactory('MockERC721').then(f => f.deploy('nft2', 'nft2'))) as MockERC721;
		const uniqueId = 123;
		const tx = await ylideMailer.createMailingFeed('768768768768121341');
		const receipt = await tx.wait();
		const feedId = String(receipt.events?.[0].args?.[0] || 0);
		const recipients = [1, 2];
		const keys = [new Uint8Array([1, 2, 3, 4, 5, 6]), new Uint8Array([6, 5, 4, 3, 2, 1])];
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		sendBulkMailArgs = [feedId, uniqueId, recipients, keys, content];
		const blocknumber = await ethers.provider.getBlockNumber();
		addMailRecipientsArgs = [feedId, uniqueId, blocknumber, 2, 10, recipients, keys];
	});

	it('Owner can set ylideMailer in YlidePay', async () => {
		await expect(ylidePay.connect(user1).setYlideMailer(ethers.Wallet.createRandom().address)).to.be.reverted;
		await ylidePay.connect(owner).setYlideMailer(ylideMailer.address);
		expect(await ylidePay.ylideMailer()).equal(ylideMailer.address);
	});

	it('Owner can set ylidePay in YlideMailer', async () => {
		await expect(ylideMailer.connect(user1).setYlidePay(ethers.Wallet.createRandom().address)).to.be.reverted;
		await ylideMailer.connect(owner).setYlidePay(ylidePay.address);
		expect(await ylideMailer.ylidePay()).equal(ylidePay.address);
		await makeSnapshot(snapshot);
	});

	it('It directly transfers ERC20 type tokens using sendBulkMail', async () => {
		await backToSnapshot(snapshot);

		await token1.connect(user1).mint(toWei(1000));
		await token2.connect(user1).mint(toWei(1000));
		await token1.connect(user1).approve(ylidePay.address, toWei(300));

		await ylidePay.connect(user1).sendBulkMailWithToken(
			...prepareSendBulkMailWithTokenArguments(sendBulkMailArgs, [
				{
					recipient: 112,
					amountOrTokenId: toWei(300),
					sendTo: user2.address,
					token: token1.address,
					tokenType: 0,
					transferType: 0,
				},
			]),
		);
		expect(await token1.balanceOf(user1.address)).equal(toWei(700));
		expect(await token1.balanceOf(user2.address)).equal(toWei(300));

		await token1.connect(user1).approve(ylidePay.address, toWei(200));
		await token2.connect(user1).approve(ylidePay.address, toWei(100));
		await ylidePay.connect(user1).sendBulkMailWithToken(
			...prepareSendBulkMailWithTokenArguments(sendBulkMailArgs, [
				{
					recipient: 112,
					amountOrTokenId: toWei(200),
					sendTo: user2.address,
					token: token1.address,
					tokenType: 0,
					transferType: 0,
				},
				{
					recipient: 113,
					amountOrTokenId: toWei(100),
					sendTo: owner.address,
					token: token2.address,
					tokenType: 0,
					transferType: 0,
				},
			]),
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

		await ylidePay.connect(user1).sendBulkMailWithToken(
			...prepareSendBulkMailWithTokenArguments(sendBulkMailArgs, [
				{
					recipient: 112,
					amountOrTokenId: 123,
					sendTo: user2.address,
					token: nft1.address,
					tokenType: 1,
					transferType: 0,
				},
			]),
		);
		expect(await nft1.balanceOf(user1.address)).equal(1);
		expect(await nft1.balanceOf(user2.address)).equal(1);
		expect(await nft1.ownerOf(123)).equal(user2.address);
		expect(await nft1.ownerOf(456)).equal(user1.address);

		await nft1.connect(user1).approve(ylidePay.address, 456);
		await nft2.connect(user1).approve(ylidePay.address, 789);
		await ylidePay.connect(user1).sendBulkMailWithToken(
			...prepareSendBulkMailWithTokenArguments(sendBulkMailArgs, [
				{
					recipient: 112,
					amountOrTokenId: 456,
					sendTo: user2.address,
					token: nft1.address,
					tokenType: 0,
					transferType: 0,
				},
				{
					recipient: 113,
					amountOrTokenId: 789,
					sendTo: owner.address,
					token: nft2.address,
					tokenType: 0,
					transferType: 0,
				},
			]),
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
		await ylidePay.connect(user1).sendBulkMailWithToken(
			...prepareSendBulkMailWithTokenArguments(sendBulkMailArgs, [
				{
					recipient: 112,
					amountOrTokenId: 123,
					sendTo: user2.address,
					token: nft1.address,
					tokenType: 1,
					transferType: 0,
				},
				{
					recipient: 113,
					amountOrTokenId: toWei(300),
					sendTo: owner.address,
					token: token1.address,
					tokenType: 0,
					transferType: 0,
				},
			]),
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

		await ylidePay.connect(user1).addMailRecipientsWithToken(
			...prepareAddMailRecipientsWithTokenArguments(addMailRecipientsArgs, [
				{
					recipient: 112,
					amountOrTokenId: toWei(300),
					sendTo: user2.address,
					token: token1.address,
					tokenType: 0,
					transferType: 0,
				},
			]),
		);
		expect(await token1.balanceOf(user1.address)).equal(toWei(700));
		expect(await token1.balanceOf(user2.address)).equal(toWei(300));

		await token1.connect(user1).approve(ylidePay.address, toWei(200));
		await ylidePay.connect(user1).addMailRecipientsWithToken(
			...prepareAddMailRecipientsWithTokenArguments(addMailRecipientsArgs, [
				{
					recipient: 112,
					amountOrTokenId: toWei(120),
					sendTo: user2.address,
					token: token1.address,
					tokenType: 0,
					transferType: 0,
				},
				{
					recipient: 113,
					amountOrTokenId: toWei(80),
					sendTo: owner.address,
					token: token1.address,
					tokenType: 0,
					transferType: 0,
				},
			]),
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

		await ylidePay.connect(user1).addMailRecipientsWithToken(
			...prepareAddMailRecipientsWithTokenArguments(addMailRecipientsArgs, [
				{
					recipient: 112,
					amountOrTokenId: 123,
					sendTo: user2.address,
					token: nft1.address,
					tokenType: 1,
					transferType: 0,
				},
			]),
		);
		expect(await nft1.balanceOf(user1.address)).equal(2);
		expect(await nft1.balanceOf(user2.address)).equal(1);
		expect(await nft1.ownerOf(123)).equal(user2.address);
		expect(await nft1.ownerOf(456)).equal(user1.address);

		await nft1.connect(user1).approve(ylidePay.address, 456);
		await nft1.connect(user1).approve(ylidePay.address, 789);
		await ylidePay.connect(user1).addMailRecipientsWithToken(
			...prepareAddMailRecipientsWithTokenArguments(addMailRecipientsArgs, [
				{
					recipient: 112,
					amountOrTokenId: 456,
					sendTo: user2.address,
					token: nft1.address,
					tokenType: 0,
					transferType: 0,
				},
				{
					recipient: 113,
					amountOrTokenId: 789,
					sendTo: owner.address,
					token: nft1.address,
					tokenType: 0,
					transferType: 0,
				},
			]),
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
		await ylidePay.connect(user1).addMailRecipientsWithToken(
			...prepareAddMailRecipientsWithTokenArguments(addMailRecipientsArgs, [
				{
					recipient: 112,
					amountOrTokenId: 123,
					sendTo: user2.address,
					token: nft1.address,
					tokenType: 0,
					transferType: 0,
				},
				{
					recipient: 113,
					amountOrTokenId: toWei(300),
					sendTo: owner.address,
					token: token1.address,
					tokenType: 0,
					transferType: 0,
				},
			]),
		);
		expect(await nft1.balanceOf(user1.address)).equal(0);
		expect(await nft1.balanceOf(user2.address)).equal(1);
		expect(await nft1.balanceOf(owner.address)).equal(0);
		expect(await nft1.ownerOf(123)).equal(user2.address);

		expect(await token1.balanceOf(user1.address)).equal(toWei(700));
		expect(await token1.balanceOf(user2.address)).equal(0);
		expect(await token1.balanceOf(owner.address)).equal(toWei(300));
	});

	it('It stakes ERC20 and ERC721 type tokens using sendBulkMail', async () => {
		await backToSnapshot(snapshot);

		await token1.connect(user1).mint(toWei(1000));
		await nft1.connect(user1).mint(123);
		await token1.connect(user1).approve(ylidePay.address, toWei(300));
		await nft1.connect(user1).approve(ylidePay.address, 123);

		await ylidePay.connect(user1).sendBulkMailWithToken(
			...prepareSendBulkMailWithTokenArguments(sendBulkMailArgs, [
				{
					recipient: 112,
					amountOrTokenId: toWei(300),
					sendTo: user2.address,
					token: token1.address,
					tokenType: 0,
					transferType: 1,
				},
				{
					recipient: 113,
					amountOrTokenId: 123,
					sendTo: user2.address,
					token: nft1.address,
					tokenType: 1,
					transferType: 1,
				},
			]),
		);
		expect(await token1.balanceOf(user1.address)).equal(toWei(700));
		expect(await token1.balanceOf(user2.address)).equal(0);
		expect(await token1.balanceOf(ylidePay.address)).equal(toWei(300));

		expect(await nft1.balanceOf(user1.address)).equal(0);
		expect(await nft1.balanceOf(user2.address)).equal(0);
		expect(await nft1.balanceOf(ylidePay.address)).equal(1);

		expect(await nft1.ownerOf(123)).equal(ylidePay.address);

		expect(await ylidePay.getUserErc20Tokens(user1.address)).deep.equal([]);
		expect(await ylidePay.getUserErc20Tokens(user2.address)).deep.equal([token1.address]);
		expect(await ylidePay.getUserErc721Tokens(user1.address)).deep.equal([]);
		expect(await ylidePay.getUserErc721Tokens(user2.address)).deep.equal([nft1.address]);

		expect(await ylidePay.getBalanceErc20(user2.address, token1.address)).equal(toWei(300));
		expect(await ylidePay.getTokenIdsErc721(user2.address, nft1.address)).deep.equal([123]);

		await expect(ylidePay.connect(user1).withdrawErc20([token1.address])).to.be.revertedWith('Not in list map');
		await expect(
			ylidePay.connect(user1).withdrawErc721([{ token: nft1.address, tokenId: 123 }]),
		).to.be.revertedWith('Not in list map');

		await ylidePay.connect(user2).withdrawErc20([token1.address]);
		await ylidePay.connect(user2).withdrawErc721([{ token: nft1.address, tokenId: 123 }]);

		expect(await token1.balanceOf(user2.address)).equal(toWei(300));
		expect(await token1.balanceOf(ylidePay.address)).equal(0);

		expect(await nft1.balanceOf(user1.address)).equal(0);
		expect(await nft1.balanceOf(user2.address)).equal(1);
		expect(await nft1.balanceOf(ylidePay.address)).equal(0);

		expect(await nft1.ownerOf(123)).equal(user2.address);

		expect(await ylidePay.getUserErc20Tokens(user1.address)).deep.equal([]);
		expect(await ylidePay.getUserErc20Tokens(user2.address)).deep.equal([]);
		expect(await ylidePay.getUserErc721Tokens(user1.address)).deep.equal([]);
		expect(await ylidePay.getUserErc721Tokens(user2.address)).deep.equal([]);

		expect(await ylidePay.getBalanceErc20(user2.address, token1.address)).equal(0);
		expect(await ylidePay.getTokenIdsErc721(user2.address, nft1.address)).deep.equal([]);
	});

	it('It stakes ERC20 and ERC721 type tokens using addMailRecipientsWithToken', async () => {
		await backToSnapshot(snapshot);

		await token1.connect(user1).mint(toWei(1000));
		await nft1.connect(user1).mint(123);
		await token1.connect(user1).approve(ylidePay.address, toWei(300));
		await nft1.connect(user1).approve(ylidePay.address, 123);

		await ylidePay.connect(user1).addMailRecipientsWithToken(
			...prepareAddMailRecipientsWithTokenArguments(addMailRecipientsArgs, [
				{
					recipient: 112,
					amountOrTokenId: toWei(300),
					sendTo: user2.address,
					token: token1.address,
					tokenType: 0,
					transferType: 1,
				},
				{
					recipient: 113,
					amountOrTokenId: 123,
					sendTo: user2.address,
					token: nft1.address,
					tokenType: 1,
					transferType: 1,
				},
			]),
		);
		expect(await token1.balanceOf(user1.address)).equal(toWei(700));
		expect(await token1.balanceOf(user2.address)).equal(0);
		expect(await token1.balanceOf(ylidePay.address)).equal(toWei(300));

		expect(await nft1.balanceOf(user1.address)).equal(0);
		expect(await nft1.balanceOf(user2.address)).equal(0);
		expect(await nft1.balanceOf(ylidePay.address)).equal(1);

		expect(await nft1.ownerOf(123)).equal(ylidePay.address);

		expect(await ylidePay.getUserErc20Tokens(user1.address)).deep.equal([]);
		expect(await ylidePay.getUserErc20Tokens(user2.address)).deep.equal([token1.address]);
		expect(await ylidePay.getUserErc721Tokens(user1.address)).deep.equal([]);
		expect(await ylidePay.getUserErc721Tokens(user2.address)).deep.equal([nft1.address]);

		expect(await ylidePay.getBalanceErc20(user2.address, token1.address)).equal(toWei(300));
		expect(await ylidePay.getTokenIdsErc721(user2.address, nft1.address)).deep.equal([123]);

		await expect(ylidePay.connect(user1).withdrawErc20([token1.address])).to.be.revertedWith('Not in list map');
		await expect(
			ylidePay.connect(user1).withdrawErc721([{ token: nft1.address, tokenId: 123 }]),
		).to.be.revertedWith('Not in list map');

		await ylidePay.connect(user2).withdrawErc20([token1.address]);
		await ylidePay.connect(user2).withdrawErc721([{ token: nft1.address, tokenId: 123 }]);

		expect(await token1.balanceOf(user2.address)).equal(toWei(300));
		expect(await token1.balanceOf(ylidePay.address)).equal(0);

		expect(await nft1.balanceOf(user1.address)).equal(0);
		expect(await nft1.balanceOf(user2.address)).equal(1);
		expect(await nft1.balanceOf(ylidePay.address)).equal(0);

		expect(await nft1.ownerOf(123)).equal(user2.address);

		expect(await ylidePay.getUserErc20Tokens(user1.address)).deep.equal([]);
		expect(await ylidePay.getUserErc20Tokens(user2.address)).deep.equal([]);
		expect(await ylidePay.getUserErc721Tokens(user1.address)).deep.equal([]);
		expect(await ylidePay.getUserErc721Tokens(user2.address)).deep.equal([]);

		expect(await ylidePay.getBalanceErc20(user2.address, token1.address)).equal(0);
		expect(await ylidePay.getTokenIdsErc721(user2.address, nft1.address)).deep.equal([]);
	});
});
