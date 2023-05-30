import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import { describe } from 'mocha';
import { YlideMailerV8 } from '../typechain-types';

describe('MailerV8', () => {
	let ylideMailer: YlideMailerV8;
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
			.getContractFactory('YlideMailerV8', owner)
			.then(factory => factory.deploy())) as YlideMailerV8;
		const tx = await ylideMailer.createMailingFeed('768768768768121341');
		const receipt = await tx.wait();
		feedId = String(receipt.events?.[0].args?.[0] || 0);
	});

	it('sendBulkMail with signature', async () => {
		const tx = await ylideMailer.connect(owner).sendBulkMail(
			feedId,
			uniqueId,
			new Array(100).fill({}).map(_ => ethers.Wallet.createRandom().address),
			new Array(100).fill(new Uint8Array([1, 2, 3, 4, 5, 6])),
			content,
		);

		await tx
			.wait()
			.then(r => r.gasUsed)
			.then(console.log);
	});
});
