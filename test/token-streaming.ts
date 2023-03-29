import { impersonateAccount, mine } from '@nomicfoundation/hardhat-network-helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers, network } from 'hardhat';
import { before, describe } from 'mocha';
import { ERC20, YlideMailerV9, YlideStreamSablierV1 } from 'typechain-types';
import {
	currentTimestamp,
	prepareAddMailRecipientsWithTokenArguments,
	prepareSendBulkMailWithTokenArguments,
	toWei6,
} from '../scripts/utils';

const USDC_ADDRESS = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
const SABLIER_ADDRESS = '0xCD18eAa163733Da39c232722cBC4E8940b1D8888';

const WHALE_USDC = '0xCFFAd3200574698b78f32232aa9D63eABD290703';

describe('Token streaming', () => {
	let usdc: ERC20;
	let ylideMailer: YlideMailerV9;
	let ylideStreamSablier: YlideStreamSablierV1;
	let owner: SignerWithAddress;
	let user1: SignerWithAddress;
	let user2: SignerWithAddress;

	let feedId: string;

	let sendBulkMailArgs: Parameters<
		YlideMailerV9['functions']['sendBulkMail(uint256,uint256,uint256[],bytes[],bytes)']
	>;

	const uniqueId = 123;
	const recipients = [1, 2];
	const keys = [new Uint8Array([1, 2, 3, 4, 5, 6]), new Uint8Array([6, 5, 4, 3, 2, 1])];
	const content = new Uint8Array([8, 7, 8, 7, 8, 7]);

	const prepareAddMailRecipientsArgs = async (
		feedId: string,
	): Promise<
		Parameters<
			YlideMailerV9['functions']['addMailRecipients(uint256,uint256,uint256,uint16,uint16,uint256[],bytes[])']
		>
	> => {
		const blocknumber = await ethers.provider.getBlockNumber();
		return [feedId, uniqueId, blocknumber, 2, 10, recipients, keys];
	};

	before(async function () {
		if ('forking' in network.config) {
			if (!network.config.forking?.enabled) {
				console.log('Skip because it is not fork');
				return this.skip();
			}
		}
		await impersonateAccount(WHALE_USDC);
		owner = await ethers.getSigner(WHALE_USDC);
		[user1, user2] = await ethers.getSigners();
		ylideMailer = (await ethers.getContractFactory('YlideMailerV9', owner).then(f => f.deploy())) as YlideMailerV9;
		ylideStreamSablier = (await ethers
			.getContractFactory('YlideStreamSablierV1', owner)
			.then(f => f.deploy())) as YlideStreamSablierV1;
		usdc = await ethers.getContractAt('ERC20', USDC_ADDRESS, owner);
		const uniqueId = 123;
		const tx = await ylideMailer.createMailingFeed('768768768768121341');
		const receipt = await tx.wait();
		feedId = String(receipt.events?.[0].args?.[0] || 0);
		const recipients = [1, 2];
		const keys = [new Uint8Array([1, 2, 3, 4, 5, 6]), new Uint8Array([6, 5, 4, 3, 2, 1])];
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		sendBulkMailArgs = [feedId, uniqueId, recipients, keys, content];
		await ylideMailer.connect(owner).setIsYlideTokenAttachment([ylideStreamSablier.address], [true]);
	});

	it('Owner can set ylideMailer in YlideStreamSablierV1', async () => {
		await expect(ylideStreamSablier.connect(user1).setYlideMailer(ethers.Wallet.createRandom().address)).to.be
			.reverted;
		await ylideStreamSablier.connect(owner).setYlideMailer(ylideMailer.address);
		expect(await ylideStreamSablier.ylideMailer()).equal(ylideMailer.address);
	});

	it('Owner should be able to set sablier in YlideStreamSablierV1', async () => {
		await expect(ylideStreamSablier.connect(user1).setSablier(ethers.Wallet.createRandom().address)).to.be.reverted;
		await ylideStreamSablier.connect(owner).setSablier(SABLIER_ADDRESS);
		expect(await ylideStreamSablier.sablier()).equal(SABLIER_ADDRESS);
	});

	it('Sender and recipient can call withdrawFromStream before it is complete + recipient withdraws all funds after stream is finished', async () => {
		const now = await currentTimestamp().then(r => r + 1000);
		const oneWeek = 3600 * 24 * 7;
		const oneWeekFromNow = now + oneWeek;
		const deposit = oneWeek * 100;

		await usdc.connect(owner).approve(ylideStreamSablier.address, deposit);
		await ylideStreamSablier.connect(owner).sendBulkMailWithToken(
			...prepareSendBulkMailWithTokenArguments(sendBulkMailArgs, [
				{
					recipient: user1.address,
					deposit,
					tokenAddress: USDC_ADDRESS,
					startTime: now,
					stopTime: oneWeekFromNow,
				},
			]),
		);
		const {
			args: { contentId },
		} = await ylideMailer
			.queryFilter(ylideMailer.filters.MailPush(null, sendBulkMailArgs[0]))
			.then(r => r[r.length - 1]);
		const stream = await ylideStreamSablier.contentIdToStreamInfo(contentId);

		expect(stream.recipient).equal(user1.address);
		expect(stream.sender).equal(owner.address);
		expect(stream.deposit).equal(deposit);
		expect(stream.tokenAddress).equal(USDC_ADDRESS);
		expect(stream.startTime).equal(now);
		expect(stream.stopTime).equal(oneWeekFromNow);
		expect(stream.deposit).equal(deposit);

		expect(
			await ylideStreamSablier
				.balance(contentId)
				.then(r => [r.balanceSender.toNumber(), r.balanceRecipient.toNumber()]),
		).deep.equal([deposit, 0]);

		await mine(100, { interval: 15 });

		const [balanceOwnerAfter1, balanceUser1After1] = await ylideStreamSablier.balance(contentId);
		expect(balanceUser1After1).gt(0);
		expect(balanceOwnerAfter1.add(balanceUser1After1)).equal(deposit);

		await expect(
			ylideStreamSablier.connect(user2).withdrawFromStream(contentId, balanceUser1After1),
		).to.be.revertedWith('caller is not the sender or the recipient of the stream');

		// recipient can withdraw from stream
		await ylideStreamSablier.connect(user1).withdrawFromStream(contentId, balanceUser1After1.sub(2));
		expect(await ylideStreamSablier.balance(contentId).then(r => r[1])).lt(balanceUser1After1);
		// sender can withdraw from stream as well
		await ylideStreamSablier
			.balance(contentId)
			.then(r => ylideStreamSablier.connect(owner).withdrawFromStream(contentId, r[1]));
		// it will be 100 because 1 second passes after previous transaction
		expect(await ylideStreamSablier.balance(contentId).then(r => r[1])).equal(100);

		// wait long to complete the stream
		await mine(100000, { interval: 150 });

		expect(await ylideStreamSablier.balance(contentId).then(r => r[0])).equal(0);
		const balanceUser1Remaining = await ylideStreamSablier.balance(contentId).then(r => r[1]);
		await ylideStreamSablier.connect(user1).withdrawFromStream(contentId, balanceUser1Remaining);

		// there is small error in Sablier therefore user can get slightly less
		expect(await usdc.balanceOf(user1.address)).gt(BigNumber.from(deposit).sub(toWei6(1)));

		await expect(ylideStreamSablier.balance(contentId)).to.be.revertedWith('stream does not exist');
		expect(await usdc.balanceOf(ylideStreamSablier.address)).equal(0);
	});

	it('Sender can cancel stream before it starts', async () => {
		const now = await currentTimestamp().then(r => r + 1000);
		const oneWeek = 3600 * 24 * 7;
		const oneWeekFromNow = now + oneWeek;
		const deposit = oneWeek * 100;

		await usdc.connect(owner).approve(ylideStreamSablier.address, deposit);
		const ownerUsdcBalanceInitial = await usdc.balanceOf(owner.address);
		await ylideStreamSablier.connect(owner).addMailRecipientsWithToken(
			...prepareAddMailRecipientsWithTokenArguments(await prepareAddMailRecipientsArgs(feedId), [
				{
					recipient: user1.address,
					deposit,
					tokenAddress: USDC_ADDRESS,
					startTime: now,
					stopTime: oneWeekFromNow,
				},
			]),
		);
		const {
			args: { contentId },
		} = await ylideMailer
			.queryFilter(ylideMailer.filters.MailPush(null, sendBulkMailArgs[0]))
			.then(r => r[r.length - 1]);

		const ownerUsdcBalanceAfter = await usdc.balanceOf(owner.address);
		expect(deposit).gt(0);
		expect(ownerUsdcBalanceAfter.add(deposit)).equal(ownerUsdcBalanceInitial);

		await ylideStreamSablier.connect(owner).cancelStream(contentId);
		expect(await usdc.balanceOf(owner.address)).equal(ownerUsdcBalanceInitial);
	});

	it('Sender can cancel stream after it has started', async () => {
		const now = await currentTimestamp().then(r => r + 1000);
		const oneWeek = 3600 * 24 * 7;
		const oneWeekFromNow = now + oneWeek;
		const deposit = oneWeek * 100;

		const user1UsdcBalance = await usdc.balanceOf(user1.address);

		await usdc.connect(owner).approve(ylideStreamSablier.address, deposit);
		await ylideStreamSablier.connect(owner).addMailRecipientsWithToken(
			...prepareAddMailRecipientsWithTokenArguments(await prepareAddMailRecipientsArgs(feedId), [
				{
					recipient: user1.address,
					deposit,
					tokenAddress: USDC_ADDRESS,
					startTime: now,
					stopTime: oneWeekFromNow,
				},
			]),
		);
		const {
			args: { contentId },
		} = await ylideMailer
			.queryFilter(ylideMailer.filters.MailPush(null, sendBulkMailArgs[0]))
			.then(r => r[r.length - 1]);

		const ownerUsdcBalanceAfter = await usdc.balanceOf(owner.address);

		await mine(100, { interval: 15 });

		const [ownerBalanceStream, user1BalanceStream] = await ylideStreamSablier.balance(contentId);

		await ylideStreamSablier.connect(owner).cancelStream(contentId);

		// sender and recipient both receive money. 100 difference because of 1 second passed
		expect(await usdc.balanceOf(user1.address)).equal(user1UsdcBalance.add(user1BalanceStream).add(100));
		expect(await usdc.balanceOf(owner.address)).equal(ownerUsdcBalanceAfter.add(ownerBalanceStream).sub(100));
	});

	it('Recipient can cancel stream before it starts', async () => {
		const now = await currentTimestamp().then(r => r + 1000);
		const oneWeek = 3600 * 24 * 7;
		const oneWeekFromNow = now + oneWeek;
		const deposit = oneWeek * 100;

		const user1UsdcBalance = await usdc.balanceOf(user1.address);

		await usdc.connect(owner).approve(ylideStreamSablier.address, deposit);
		const ownerUsdcBalanceInitial = await usdc.balanceOf(owner.address);
		await ylideStreamSablier.connect(owner).sendBulkMailWithToken(
			...prepareSendBulkMailWithTokenArguments(sendBulkMailArgs, [
				{
					recipient: user1.address,
					deposit,
					tokenAddress: USDC_ADDRESS,
					startTime: now,
					stopTime: oneWeekFromNow,
				},
			]),
		);
		const {
			args: { contentId },
		} = await ylideMailer
			.queryFilter(ylideMailer.filters.MailPush(null, sendBulkMailArgs[0]))
			.then(r => r[r.length - 1]);

		const ownerUsdcBalanceAfter = await usdc.balanceOf(owner.address);
		expect(deposit).gt(0);
		expect(ownerUsdcBalanceAfter.add(deposit)).equal(ownerUsdcBalanceInitial);

		await ylideStreamSablier.connect(user1).cancelStream(contentId);
		expect(await usdc.balanceOf(owner.address)).equal(ownerUsdcBalanceInitial);
		expect(await usdc.balanceOf(user1.address)).equal(user1UsdcBalance);
	});

	it('Recipient can cancel stream after it has started', async () => {
		const now = await currentTimestamp().then(r => r + 1000);
		const oneWeek = 3600 * 24 * 7;
		const oneWeekFromNow = now + oneWeek;
		const deposit = oneWeek * 100;

		const user1UsdcBalance = await usdc.balanceOf(user1.address);

		await usdc.connect(owner).approve(ylideStreamSablier.address, deposit);
		await ylideStreamSablier.connect(owner).sendBulkMailWithToken(
			...prepareSendBulkMailWithTokenArguments(sendBulkMailArgs, [
				{
					recipient: user1.address,
					deposit,
					tokenAddress: USDC_ADDRESS,
					startTime: now,
					stopTime: oneWeekFromNow,
				},
			]),
		);
		const {
			args: { contentId },
		} = await ylideMailer
			.queryFilter(ylideMailer.filters.MailPush(null, sendBulkMailArgs[0]))
			.then(r => r[r.length - 1]);

		const ownerUsdcBalanceAfter = await usdc.balanceOf(owner.address);

		await mine(100, { interval: 15 });

		const [ownerBalanceStream, user1BalanceStream] = await ylideStreamSablier.balance(contentId);

		await ylideStreamSablier.connect(user1).cancelStream(contentId);

		// sender and recipient both receive money. 100 difference because of 1 second passed
		expect(await usdc.balanceOf(user1.address)).equal(user1UsdcBalance.add(user1BalanceStream).add(100));
		expect(await usdc.balanceOf(owner.address)).equal(ownerUsdcBalanceAfter.add(ownerBalanceStream).sub(100));
	});

	it('cancelStreamAndSendBulkMail', async () => {
		const now = await currentTimestamp().then(r => r + 1000);
		const oneWeek = 3600 * 24 * 7;
		const oneWeekFromNow = now + oneWeek;
		const deposit = oneWeek * 100;

		await usdc.connect(owner).approve(ylideStreamSablier.address, deposit);
		const ownerUsdcBalanceInitial = await usdc.balanceOf(owner.address);
		await ylideStreamSablier.connect(owner).sendBulkMailWithToken(
			...prepareSendBulkMailWithTokenArguments(sendBulkMailArgs, [
				{
					recipient: user1.address,
					deposit,
					tokenAddress: USDC_ADDRESS,
					startTime: now,
					stopTime: oneWeekFromNow,
				},
			]),
		);
		const {
			args: { contentId },
		} = await ylideMailer
			.queryFilter(ylideMailer.filters.MailPush(null, sendBulkMailArgs[0]))
			.then(r => r[r.length - 1]);

		const ownerUsdcBalanceAfter = await usdc.balanceOf(owner.address);
		expect(deposit).gt(0);
		expect(ownerUsdcBalanceAfter.add(deposit)).equal(ownerUsdcBalanceInitial);

		const args = [...sendBulkMailArgs] as any;
		args[5] = contentId;
		await ylideStreamSablier
			.connect(owner)
			.cancelStreamAndSendBulkMail(
				...(args as Parameters<YlideStreamSablierV1['functions']['cancelStreamAndSendBulkMail']>),
			);
		expect(await usdc.balanceOf(owner.address)).equal(ownerUsdcBalanceInitial);
	});

	it('cancelStreamAndAddMailRecipients', async () => {
		const now = await currentTimestamp().then(r => r + 1000);
		const oneWeek = 3600 * 24 * 7;
		const oneWeekFromNow = now + oneWeek;
		const deposit = oneWeek * 100;

		await usdc.connect(owner).approve(ylideStreamSablier.address, deposit);
		const ownerUsdcBalanceInitial = await usdc.balanceOf(owner.address);
		await ylideStreamSablier.connect(owner).sendBulkMailWithToken(
			...prepareSendBulkMailWithTokenArguments(sendBulkMailArgs, [
				{
					recipient: user1.address,
					deposit,
					tokenAddress: USDC_ADDRESS,
					startTime: now,
					stopTime: oneWeekFromNow,
				},
			]),
		);
		const {
			args: { contentId },
		} = await ylideMailer
			.queryFilter(ylideMailer.filters.MailPush(null, sendBulkMailArgs[0]))
			.then(r => r[r.length - 1]);

		const ownerUsdcBalanceAfter = await usdc.balanceOf(owner.address);
		expect(deposit).gt(0);
		expect(ownerUsdcBalanceAfter.add(deposit)).equal(ownerUsdcBalanceInitial);

		const args = [...(await prepareAddMailRecipientsArgs(feedId))] as any;
		args[7] = contentId;
		await ylideStreamSablier
			.connect(owner)
			.cancelStreamAndAddMailRecipients(
				...(args as Parameters<YlideStreamSablierV1['functions']['cancelStreamAndAddMailRecipients']>),
			);
		expect(await usdc.balanceOf(owner.address)).equal(ownerUsdcBalanceInitial);
	});
});
