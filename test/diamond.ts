import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { FacetCut, FacetCutAction } from '../scripts/types';
import { getSelectors, mine, whitelistedOneself } from '../scripts/utils';
import { MockERC20 } from '../typechain-types';

describe('Diamond', () => {
	let owner: SignerWithAddress;
	let user1: SignerWithAddress;
	let user2: SignerWithAddress;
	let registrar1: SignerWithAddress;
	let registrar2: SignerWithAddress;
	let referrerInterface: SignerWithAddress;
	let erc20: MockERC20;
	let erc20_2: MockERC20;
	let diamondAddress: string;
	let feedId: string;

	before(async () => {
		[owner, user1, user2, registrar1, registrar2, referrerInterface] = await ethers.getSigners();
	});

	it('should deploy diamond and facets', async () => {
		erc20 = await ethers.getContractFactory('MockERC20', owner).then(f => f.deploy('mock', 'token'));
		erc20_2 = await ethers.getContractFactory('MockERC20', owner).then(f => f.deploy('mock', 'token'));
		// deploy DiamondCutFacet
		const DiamondCutFacet = await ethers.getContractFactory('DiamondCutFacet', owner);
		const diamondCutFacet = await DiamondCutFacet.deploy();
		await diamondCutFacet.deployed();

		// deploy Diamond
		const Diamond = await ethers.getContractFactory('Ylide', owner);
		const diamond = await Diamond.deploy(owner.address, diamondCutFacet.address);
		await diamond.deployed();
		diamondAddress = diamond.address;

		// deploy facets
		const FacetNames = ['DiamondLoupeFacet', 'ConfigFacet', 'MockMailerFacet', 'RegistryFacet', 'StakeFacet'];
		const cut: FacetCut[] = [];
		for (const FacetName of FacetNames) {
			const Facet = await ethers.getContractFactory(FacetName);
			const facet = await Facet.deploy();
			await facet.deployed();
			cut.push({
				facetAddress: facet.address,
				action: FacetCutAction.Add,
				functionSelectors: getSelectors(facet),
			});
		}
		// cut diamond facets
		const diamondCut = await ethers.getContractAt('DiamondCutFacet', diamond.address);
		await diamondCut.diamondCut(cut, ethers.constants.AddressZero, []);
	});

	it('should exchange facet', async () => {
		const configFacet = await ethers.getContractAt('ConfigFacet', diamondAddress);
		const mockMailerFacet = await ethers.getContractAt('MockMailerFacet', diamondAddress);
		await mockMailerFacet.connect(user1).setNewcomerBonus(1);
		expect(await mockMailerFacet.version()).equal(100);
		expect(await configFacet.newcomerBonus()).equal(1);
		const mailerFacet = await ethers
			.getContractFactory('MailerFacet')
			.then(f => f.deploy())
			.then(c => c.deployed());
		const diamondCut = await ethers.getContractAt('DiamondCutFacet', diamondAddress);
		// only owner can exchange facets
		await expect(
			diamondCut.connect(user1).diamondCut(
				[
					{
						facetAddress: ethers.constants.AddressZero,
						action: FacetCutAction.Remove,
						functionSelectors: getSelectors(mockMailerFacet),
					},
					{
						facetAddress: mailerFacet.address,
						action: FacetCutAction.Add,
						functionSelectors: getSelectors(mailerFacet),
					},
				],
				ethers.constants.AddressZero,
				[],
			),
		).to.be.revertedWithCustomError(diamondCut, 'MustBeContractOwner');
		await diamondCut.connect(owner).diamondCut(
			[
				{
					facetAddress: ethers.constants.AddressZero,
					action: FacetCutAction.Remove,
					functionSelectors: getSelectors(mockMailerFacet),
				},
				{
					facetAddress: mailerFacet.address,
					action: FacetCutAction.Add,
					functionSelectors: getSelectors(mailerFacet),
				},
			],
			ethers.constants.AddressZero,
			[],
		);
		expect(await mockMailerFacet.version()).equal(9);
		expect(await configFacet.newcomerBonus()).equal(1);
		await configFacet.setBonuses(2, 3);
		expect(await configFacet.newcomerBonus()).equal(2);
		expect(await configFacet.referrerBonus()).equal(3);
	});

	it('should add key to registry', async () => {
		const configFacet = await ethers.getContractAt('ConfigFacet', diamondAddress);
		const registryFacet = await ethers.getContractAt('RegistryFacet', diamondAddress);
		const publicKey = 123;
		const keyVersion = 1;
		expect(await whitelistedOneself(configFacet, user1.address)).equal(false);
		expect(await whitelistedOneself(configFacet, user2.address)).equal(false);
		await registryFacet.connect(user1).attachPublicKey(publicKey, keyVersion, registrar1.address);
		await registryFacet.connect(user2).attachPublicKey(publicKey, keyVersion, registrar2.address);
		// user should have whitelisted themselves
		expect(await whitelistedOneself(configFacet, user1.address)).equal(true);
		expect(await whitelistedOneself(configFacet, user2.address)).equal(true);
		const registryInfo = await configFacet.addressToPublicKey(user1.address);
		expect(registryInfo.publicKey).equal(publicKey);
		expect(registryInfo.keyVersion).equal(keyVersion);
		expect(registryInfo.registrar).equal(registrar1.address);
		const registryInfo2 = await configFacet.addressToPublicKey(user2.address);
		expect(registryInfo2.publicKey).equal(publicKey);
		expect(registryInfo2.keyVersion).equal(keyVersion);
		expect(registryInfo2.registrar).equal(registrar2.address);
	});

	it('should create mailing feed', async () => {
		const configFacet = await ethers.getContractAt('ConfigFacet', diamondAddress);
		const mailerFacet = await ethers.getContractAt('MailerFacet', diamondAddress);
		const tx = await mailerFacet.connect(owner).createMailingFeed('768768768768121341');
		const receipt = await tx.wait();
		feedId = String(receipt.events?.[0].args?.[0] || 0);
		const feed = await configFacet.mailingFeeds(feedId);
		expect(feed.owner).equal(owner.address);
		expect(feed.beneficiary).equal(owner.address);
		expect(feed.recipientFee).equal(0);
	});

	it('should send bulk mail', async () => {
		const recKeySups = [
			{
				recipient: user2.address,
				key: '0x0102',
				supplement: '0x',
			},
			{
				recipient: owner.address,
				key: '0x010203',
				supplement: '0x',
			},
		];
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		const mailerFacet = await ethers.getContractAt('MailerFacet', diamondAddress);
		await mailerFacet.connect(user1).sendBulkMail(feedId, 123, recKeySups, ethers.constants.AddressZero, content);
		const mailEvents = await mailerFacet.queryFilter(mailerFacet.filters.MailPush(null, feedId));

		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user1.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);
		}
	});

	it('should send 100 bulk mail', async () => {
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		const mailerFacet = await ethers.getContractAt('MailerFacet', diamondAddress);
		await mailerFacet.connect(user1).sendBulkMail(
			feedId,
			123,
			new Array(100).fill({}).map(e => ({
				recipient: ethers.Wallet.createRandom().address,
				key: '0x0102',
				supplement: '0x',
			})),
			ethers.constants.AddressZero,
			content,
		);
	});

	it('should add mail recipients', async () => {
		const recKeySups = [
			{
				recipient: user2.address,
				key: '0x0102',
				supplement: '0x',
			},
			{
				recipient: owner.address,
				key: '0x010203',
				supplement: '0x',
			},
		];
		const mailerFacet = await ethers.getContractAt('MailerFacet', diamondAddress);

		const currentBlock = await ethers.provider.getBlockNumber();
		await mailerFacet
			.connect(user1)
			.addMailRecipients(feedId, 123, recKeySups, ethers.constants.AddressZero, currentBlock, 20, 200);
		const mailEvents = await mailerFacet.queryFilter(mailerFacet.filters.MailPush(null, feedId), currentBlock + 1);
		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user1.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);
		}
	});

	it('should manage pay wall', async () => {
		const configFacet = await ethers.getContractAt('ConfigFacet', diamondAddress);

		await expect(
			configFacet.connect(user1).addAllowedTokens([user2.address, erc20.address, owner.address, erc20_2.address]),
		).to.be.revertedWithCustomError(configFacet, 'MustBeContractOwner');
		await configFacet
			.connect(owner)
			.addAllowedTokens([user2.address, erc20.address, owner.address, erc20_2.address]);
		expect(await configFacet.allowedTokens()).deep.equal([
			user2.address,
			erc20.address,
			owner.address,
			erc20_2.address,
		]);

		await expect(
			configFacet.connect(user1).setPaywallDefault([
				{ token: user2.address, amount: 1 },
				{ token: owner.address, amount: 2 },
				{ token: erc20.address, amount: 999 },
			]),
		).to.be.revertedWithCustomError(configFacet, 'MustBeContractOwner');
		await configFacet.connect(owner).setPaywallDefault([
			{ token: user2.address, amount: 1 },
			{ token: owner.address, amount: 2 },
			{ token: erc20.address, amount: 999 },
		]);

		expect(await configFacet.defaultPaywallTokenToAmount(user2.address)).equal(1);
		expect(await configFacet.defaultPaywallTokenToAmount(erc20.address)).equal(999);
		expect(await configFacet.defaultPaywallTokenToAmount(owner.address)).equal(2);

		await configFacet.connect(owner).setPaywallDefault([
			{ token: user2.address, amount: 0 },
			{ token: owner.address, amount: 0 },
			{ token: erc20.address, amount: 0 },
		]);

		expect(await configFacet.defaultPaywallTokenToAmount(user2.address)).equal(0);
		expect(await configFacet.defaultPaywallTokenToAmount(erc20.address)).equal(0);
		expect(await configFacet.defaultPaywallTokenToAmount(owner.address)).equal(0);

		await configFacet.connect(user2).setPaywall([
			{ token: user2.address, amount: 1 },
			{ token: owner.address, amount: 2 },
			{ token: erc20.address, amount: 999 },
		]);

		expect(await configFacet.recipientToPaywallTokenToAmount(user2.address, user2.address)).equal(1);
		expect(await configFacet.recipientToPaywallTokenToAmount(user2.address, erc20.address)).equal(999);
		expect(await configFacet.recipientToPaywallTokenToAmount(user2.address, owner.address)).equal(2);

		await configFacet.connect(user2).setPaywall([
			{ token: user2.address, amount: 0 },
			{ token: owner.address, amount: 3 },
		]);

		expect(await configFacet.recipientToPaywallTokenToAmount(user2.address, user2.address)).equal(0);
		expect(await configFacet.recipientToPaywallTokenToAmount(user2.address, erc20.address)).equal(999);
		expect(await configFacet.recipientToPaywallTokenToAmount(user2.address, owner.address)).equal(3);

		await configFacet.connect(user2).setPaywall([
			{ token: erc20.address, amount: 1000 },
			{ token: owner.address, amount: 0 },
			{ token: erc20_2.address, amount: 2000 },
		]);

		expect(await configFacet.recipientToPaywallTokenToAmount(user2.address, user2.address)).equal(0);
		expect(await configFacet.recipientToPaywallTokenToAmount(user2.address, erc20.address)).equal(1000);
		expect(await configFacet.recipientToPaywallTokenToAmount(user2.address, owner.address)).equal(0);
		expect(await configFacet.recipientToPaywallTokenToAmount(user2.address, erc20_2.address)).equal(2000);

		await expect(
			configFacet.connect(user1).removeAllowedTokens([user2.address, owner.address]),
		).to.be.revertedWithCustomError(configFacet, 'MustBeContractOwner');
		await configFacet.connect(owner).removeAllowedTokens([user2.address, owner.address]);
		expect(await configFacet.allowedTokens()).deep.equal([erc20_2.address, erc20.address]);
	});

	it('should correctly set fees for pay for attention', async () => {
		const configFacet = await ethers.getContractAt('ConfigFacet', diamondAddress);
		await expect(configFacet.connect(user1).setStakeLockUpPeriod(100)).to.be.revertedWithCustomError(
			configFacet,
			'MustBeContractOwner',
		);
		await configFacet.connect(owner).setStakeLockUpPeriod(100);
		// 4% ylide commission
		await expect(configFacet.connect(user1).setYlideCommissionPercentage(400)).to.be.revertedWithCustomError(
			configFacet,
			'MustBeContractOwner',
		);
		await configFacet.connect(owner).setYlideCommissionPercentage(400);
		// 6% registrar commission
		await configFacet.connect(registrar1).setRegistrarToCommissionPercentage(600);
		await configFacet.connect(registrar2).setRegistrarToCommissionPercentage(600);

		expect(await configFacet.stakeLockUpPeriod()).equal(100);
		expect(await configFacet.ylideCommissionPercentage()).equal(400);
		expect(await configFacet.registrarToCommissionPercentage(registrar1.address)).equal(600);
		expect(await configFacet.registrarToCommissionPercentage(registrar2.address)).equal(600);
	});

	it('should send bulk mail with pay for attention (default = 0) + cancel by sender', async () => {
		const configFacet = await ethers.getContractAt('ConfigFacet', diamondAddress);
		const stakeFacet = await ethers.getContractAt('StakeFacet', diamondAddress);
		const mailerFacet = await ethers.getContractAt('MailerFacet', diamondAddress);

		expect(await configFacet.allowedTokens()).deep.equal([erc20_2.address, erc20.address]);
		expect(await configFacet.defaultPaywallTokenToAmount(erc20.address)).equal(0);
		expect(await configFacet.defaultPaywallTokenToAmount(erc20_2.address)).equal(0);
		expect(await configFacet.isAllowedToken(erc20.address)).equal(true);
		expect(await configFacet.isAllowedToken(erc20_2.address)).equal(true);
		const user2PaywallInfo = await configFacet.getRecipientPaywallInfo(user2.address, user1.address);
		expect(user2PaywallInfo[0].token).equal(erc20_2.address);
		expect(user2PaywallInfo[0].amount).equal(2200);
		expect(user2PaywallInfo[1].token).equal(erc20.address);
		expect(user2PaywallInfo[1].amount).equal(1100);
		const ownerPaywallInfo = await configFacet.getRecipientPaywallInfo(owner.address, user1.address);
		expect(ownerPaywallInfo[0].token).equal(erc20_2.address);
		expect(ownerPaywallInfo[0].amount).equal(0);
		expect(ownerPaywallInfo[1].token).equal(erc20.address);
		expect(ownerPaywallInfo[1].amount).equal(0);

		await erc20.connect(user1).mint(1100);
		await erc20.connect(user1).approve(diamondAddress, 1100);
		expect(await erc20.balanceOf(user2.address)).equal(0);
		expect(await erc20.balanceOf(user1.address)).equal(1100);
		const recKeySups = [
			{
				recipient: user2.address,
				key: '0x0102',
				supplement: '0x',
			},
			{
				recipient: owner.address,
				key: '0x010203',
				supplement: '0x',
			},
		];
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		await mailerFacet.connect(user1).sendBulkMail(feedId, 123, recKeySups, erc20.address, content);
		expect(await erc20.balanceOf(user2.address)).equal(0);
		expect(await erc20.balanceOf(user1.address)).equal(0);
		expect(await erc20.balanceOf(diamondAddress)).equal(1100);

		const currentBlock = await ethers.provider.getBlockNumber();
		const mailEvents = await mailerFacet.queryFilter(mailerFacet.filters.MailPush(null, feedId), currentBlock + 1);
		let contentId = BigNumber.from(0);
		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user1.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);
			if (mailEvents[i].args.recipient.eq(user2.address)) {
				contentId = mailEvents[i].args.contentId;
			}
		}

		const timestamp = await ethers.provider.getBlock(currentBlock).then(block => block.timestamp);

		const lockupPeriod = await configFacet.stakeLockUpPeriod();

		const stakeInfoSender = await configFacet.contentIdToStakeInfoSender(contentId);
		expect(stakeInfoSender.token).equal(erc20.address);
		expect(stakeInfoSender.sender).equal(user1.address);
		expect(stakeInfoSender.stakeBlockedUntil).equal(lockupPeriod.add(timestamp));
		expect(stakeInfoSender.canceled).to.be.false;

		const stakeInfoRecipient = await configFacet.contentIdToRecipientToStakeInfo(contentId, user2.address);
		expect(stakeInfoRecipient.amount).equal(1000);
		expect(stakeInfoSender.canceled).to.be.false;

		await expect(
			stakeFacet.connect(owner).cancel([{ contentId: contentId, recipient: user2.address }]),
		).to.be.revertedWithCustomError(stakeFacet, 'NotSender');
		await expect(
			stakeFacet.connect(user1).cancel([{ contentId: contentId, recipient: user2.address }]),
		).to.be.revertedWithCustomError(stakeFacet, 'StakeLockUp');

		await mine(lockupPeriod.add(1).toNumber());

		await stakeFacet.connect(user1).cancel([{ contentId: contentId, recipient: user2.address }]);
		await expect(
			stakeFacet.connect(user1).cancel([{ contentId: contentId, recipient: user2.address }]),
		).to.be.revertedWithCustomError(stakeFacet, 'NothingToWithdraw');
		await expect(
			stakeFacet
				.connect(user2)
				.claim([contentId], { interfaceAddress: user2.address, interfaceCommissionPercentage: 4000 }),
		).to.be.revertedWithCustomError(stakeFacet, 'NothingToWithdraw');
		expect(await erc20.balanceOf(user1.address)).equal(1100);
		expect(await erc20.balanceOf(user2.address)).equal(0);
		expect(await erc20.balanceOf(diamondAddress)).equal(0);

		const stakeInfoSenderAfter = await configFacet.contentIdToStakeInfoSender(contentId);
		expect(stakeInfoSenderAfter.canceled).to.be.true;
	});

	it('should send bulk mail with pay for attention (default = 0) + claim', async () => {
		const configFacet = await ethers.getContractAt('ConfigFacet', diamondAddress);
		const stakeFacet = await ethers.getContractAt('StakeFacet', diamondAddress);
		const mailerFacet = await ethers.getContractAt('MailerFacet', diamondAddress);

		expect(await configFacet.allowedTokens()).deep.equal([erc20_2.address, erc20.address]);
		expect(await configFacet.defaultPaywallTokenToAmount(erc20.address)).equal(0);
		expect(await configFacet.defaultPaywallTokenToAmount(erc20_2.address)).equal(0);
		expect(await configFacet.isAllowedToken(erc20.address)).equal(true);
		expect(await configFacet.isAllowedToken(erc20_2.address)).equal(true);
		const user2PaywallInfo = await configFacet.getRecipientPaywallInfo(user2.address, user1.address);
		expect(user2PaywallInfo[0].token).equal(erc20_2.address);
		expect(user2PaywallInfo[0].amount).equal(2200);
		expect(user2PaywallInfo[1].token).equal(erc20.address);
		expect(user2PaywallInfo[1].amount).equal(1100);
		const ownerPaywallInfo = await configFacet.getRecipientPaywallInfo(owner.address, user1.address);
		expect(ownerPaywallInfo[0].token).equal(erc20_2.address);
		expect(ownerPaywallInfo[0].amount).equal(0);
		expect(ownerPaywallInfo[1].token).equal(erc20.address);
		expect(ownerPaywallInfo[1].amount).equal(0);

		await erc20.connect(user1).approve(diamondAddress, 1100);
		expect(await erc20.balanceOf(user2.address)).equal(0);
		expect(await erc20.balanceOf(user1.address)).equal(1100);
		expect(await erc20.balanceOf(diamondAddress)).equal(0);
		const recKeySups = [
			{
				recipient: user2.address,
				key: '0x0102',
				supplement: '0x',
			},
			{
				recipient: owner.address,
				key: '0x010203',
				supplement: '0x',
			},
		];
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		await mailerFacet.connect(user1).sendBulkMail(feedId, 123, recKeySups, erc20.address, content);
		expect(await erc20.balanceOf(user2.address)).equal(0);
		expect(await erc20.balanceOf(user1.address)).equal(0);

		const currentBlock = await ethers.provider.getBlockNumber();
		const mailEvents = await mailerFacet.queryFilter(mailerFacet.filters.MailPush(null, feedId), currentBlock + 1);
		let contentId = BigNumber.from(0);
		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user1.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);
			if (mailEvents[i].args.recipient.eq(user2.address)) {
				contentId = mailEvents[i].args.contentId;
			}
		}

		const timestamp = await ethers.provider.getBlock(currentBlock).then(block => block.timestamp);
		const lockupPeriod = await configFacet.stakeLockUpPeriod();

		const stakeInfoSender = await configFacet.contentIdToStakeInfoSender(contentId);
		expect(stakeInfoSender.token).equal(erc20.address);
		expect(stakeInfoSender.sender).equal(user1.address);
		expect(stakeInfoSender.stakeBlockedUntil).equal(lockupPeriod.add(timestamp));
		expect(stakeInfoSender.canceled).to.be.false;

		const stakeInfoRecipient = await configFacet.contentIdToRecipientToStakeInfo(contentId, user2.address);
		expect(stakeInfoRecipient.amount).equal(1000);
		expect(stakeInfoRecipient.claimed).to.be.false;

		await expect(
			stakeFacet.connect(owner).claim([contentId], {
				interfaceAddress: referrerInterface.address,
				// 40% interface commission
				interfaceCommissionPercentage: 4000,
			}),
		).to.be.revertedWithCustomError(stakeFacet, 'NoRegistrar');

		await expect(
			stakeFacet.connect(user2).claim([contentId.add(1)], {
				interfaceAddress: referrerInterface.address,
				// 40% interface commission
				interfaceCommissionPercentage: 4000,
			}),
		).to.be.revertedWithCustomError(stakeFacet, 'NothingToWithdraw');
		await expect(
			stakeFacet.connect(user2).claim([contentId], {
				interfaceAddress: ethers.constants.AddressZero,
				// 40% interface commission
				interfaceCommissionPercentage: 4000,
			}),
		).to.be.revertedWithCustomError(stakeFacet, 'NoInterface');

		await stakeFacet.connect(user2).claim([contentId], {
			interfaceAddress: referrerInterface.address,
			// 40% interface commission
			interfaceCommissionPercentage: 4000,
		});

		await expect(
			stakeFacet.connect(user2).claim([contentId], {
				interfaceAddress: referrerInterface.address,
				// 40% interface commission
				interfaceCommissionPercentage: 4000,
			}),
		).to.be.revertedWithCustomError(stakeFacet, 'NothingToWithdraw');
		await expect(
			stakeFacet.connect(user1).cancel([{ contentId: contentId, recipient: user2.address }]),
		).to.be.revertedWithCustomError(stakeFacet, 'NothingToWithdraw');

		expect(await erc20.balanceOf(user2.address)).equal(600);
		expect(await erc20.balanceOf(diamondAddress)).equal(500);
		expect(await configFacet.addressToTokenToAmount(referrerInterface.address, erc20.address)).equal(400);
		expect(await configFacet.addressToTokenToAmount(owner.address, erc20.address)).equal(40);
		expect(await configFacet.addressToTokenToAmount(registrar2.address, erc20.address)).equal(60);

		await stakeFacet.connect(referrerInterface).withdraw(erc20.address);
		await stakeFacet.connect(owner).withdraw(erc20.address);
		await stakeFacet.connect(registrar2).withdraw(erc20.address);

		await expect(stakeFacet.connect(referrerInterface).withdraw(erc20.address)).to.be.revertedWithCustomError(
			stakeFacet,
			'NothingToWithdraw',
		);
		await expect(stakeFacet.connect(owner).withdraw(erc20.address)).to.be.revertedWithCustomError(
			stakeFacet,
			'NothingToWithdraw',
		);
		await expect(stakeFacet.connect(registrar2).withdraw(erc20.address)).to.be.revertedWithCustomError(
			stakeFacet,
			'NothingToWithdraw',
		);
		await expect(stakeFacet.connect(registrar1).withdraw(erc20.address)).to.be.revertedWithCustomError(
			stakeFacet,
			'NothingToWithdraw',
		);

		expect(await configFacet.addressToTokenToAmount(referrerInterface.address, erc20.address)).equal(0);
		expect(await configFacet.addressToTokenToAmount(owner.address, erc20.address)).equal(0);
		expect(await configFacet.addressToTokenToAmount(registrar2.address, erc20.address)).equal(0);

		expect(await erc20.balanceOf(diamondAddress)).equal(0);
		expect(await erc20.balanceOf(referrerInterface.address)).equal(400);
		expect(await erc20.balanceOf(owner.address)).equal(40);
		expect(await erc20.balanceOf(registrar2.address)).equal(60);
	});

	it('should whitelist sender and send bulk mail without pay for attention (default = 0)', async () => {
		const configFacet = await ethers.getContractAt('ConfigFacet', diamondAddress);
		const mailerFacet = await ethers.getContractAt('MailerFacet', diamondAddress);
		const stakeFacet = await ethers.getContractAt('StakeFacet', diamondAddress);

		await configFacet.connect(user2).whitelistSenders([{ sender: user1.address, status: true }]);

		expect(await configFacet.recipientToWhitelistedSender(user2.address, user1.address)).equal(true);

		expect(await configFacet.allowedTokens()).deep.equal([erc20_2.address, erc20.address]);
		expect(await configFacet.defaultPaywallTokenToAmount(erc20.address)).equal(0);
		expect(await configFacet.defaultPaywallTokenToAmount(erc20_2.address)).equal(0);
		expect(await configFacet.isAllowedToken(erc20.address)).equal(true);
		expect(await configFacet.isAllowedToken(erc20_2.address)).equal(true);
		const user2PaywallInfo = await configFacet.getRecipientPaywallInfo(user2.address, user1.address);
		expect(user2PaywallInfo[0].token).equal(erc20_2.address);
		expect(user2PaywallInfo[0].amount).equal(0);
		expect(user2PaywallInfo[1].token).equal(erc20.address);
		expect(user2PaywallInfo[1].amount).equal(0);
		const ownerPaywallInfo = await configFacet.getRecipientPaywallInfo(owner.address, user1.address);
		expect(ownerPaywallInfo[0].token).equal(erc20_2.address);
		expect(ownerPaywallInfo[0].amount).equal(0);
		expect(ownerPaywallInfo[1].token).equal(erc20.address);
		expect(ownerPaywallInfo[1].amount).equal(0);

		await erc20.connect(user1).mint(1100);
		await erc20.connect(user1).approve(diamondAddress, 1100);
		expect(await erc20.balanceOf(diamondAddress)).equal(0);
		expect(await erc20.balanceOf(user2.address)).equal(600);
		expect(await erc20.balanceOf(user1.address)).equal(1100);
		const recKeySups = [
			{
				recipient: user2.address,
				key: '0x0102',
				supplement: '0x',
			},
			{
				recipient: owner.address,
				key: '0x010203',
				supplement: '0x',
			},
		];
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		await mailerFacet.connect(user1).sendBulkMail(feedId, 123, recKeySups, erc20.address, content);
		expect(await erc20.balanceOf(diamondAddress)).equal(0);
		expect(await erc20.balanceOf(user2.address)).equal(600);
		expect(await erc20.balanceOf(user1.address)).equal(1100);

		const currentBlock = await ethers.provider.getBlockNumber();
		const mailEvents = await mailerFacet.queryFilter(mailerFacet.filters.MailPush(null, feedId), currentBlock + 1);
		let contentId = BigNumber.from(0);
		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user1.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);
			if (mailEvents[i].args.recipient.eq(user2.address)) {
				contentId = mailEvents[i].args.contentId;
			}
		}

		const stakeInfoSender = await configFacet.contentIdToStakeInfoSender(contentId);
		expect(stakeInfoSender.token).equal(ethers.constants.AddressZero);
		expect(stakeInfoSender.sender).equal(ethers.constants.AddressZero);
		expect(stakeInfoSender.stakeBlockedUntil).equal(0);
		expect(stakeInfoSender.canceled).to.be.false;

		const result = await configFacet.contentIdToRecipientToStakeInfo(contentId, user2.address);
		expect(result.amount).equal(0);

		await expect(
			stakeFacet.connect(user2).claim([contentId], {
				interfaceAddress: referrerInterface.address,
				// 40% interface commission
				interfaceCommissionPercentage: 4000,
			}),
		).to.be.revertedWithCustomError(stakeFacet, 'NothingToWithdraw');
	});

	it('should send bulk mail with default pay for attention (custom is disabled)', async () => {
		const configFacet = await ethers.getContractAt('ConfigFacet', diamondAddress);
		const mailerFacet = await ethers.getContractAt('MailerFacet', diamondAddress);

		await configFacet.connect(owner).setPaywallDefault([{ token: erc20.address, amount: 100 }]);
		expect(await configFacet.recipientToPaywallTokenToAmount(user1.address, erc20.address)).equal(0);

		expect(await configFacet.allowedTokens()).deep.equal([erc20_2.address, erc20.address]);
		expect(await configFacet.defaultPaywallTokenToAmount(erc20.address)).equal(100);
		expect(await configFacet.defaultPaywallTokenToAmount(erc20_2.address)).equal(0);
		expect(await configFacet.isAllowedToken(erc20.address)).equal(true);
		expect(await configFacet.isAllowedToken(erc20_2.address)).equal(true);
		const user2PaywallInfo = await configFacet.getRecipientPaywallInfo(user1.address, user2.address);
		expect(user2PaywallInfo[0].token).equal(erc20_2.address);
		expect(user2PaywallInfo[0].amount).equal(0);
		expect(user2PaywallInfo[1].token).equal(erc20.address);
		expect(user2PaywallInfo[1].amount).equal(110);

		await erc20.connect(user2).mint(1100);
		const user2Balance = await erc20.balanceOf(user2.address);
		await erc20.connect(user2).approve(diamondAddress, 1100);
		expect(await erc20.balanceOf(user1.address)).equal(1100);

		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		const recKeySups = [
			{
				recipient: user1.address,
				key: '0x0102',
				supplement: '0x',
			},
		];
		await mailerFacet.connect(user2).sendBulkMail(feedId, 123, recKeySups, erc20.address, content);
		expect(await erc20.balanceOf(user2.address)).equal(user2Balance.sub(110));
		expect(await erc20.balanceOf(user1.address)).equal(1100);

		const currentBlock = await ethers.provider.getBlockNumber();
		const mailEvents = await mailerFacet.queryFilter(mailerFacet.filters.MailPush(null, feedId), currentBlock + 1);
		let contentId = BigNumber.from(0);
		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user2.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);
			if (mailEvents[i].args.recipient.eq(user1.address)) {
				contentId = mailEvents[i].args.contentId;
			}
		}

		const timestamp = await ethers.provider.getBlock(currentBlock).then(block => block.timestamp);

		const lockupPeriod = await configFacet.stakeLockUpPeriod();

		const stakeInfoSender = await configFacet.contentIdToStakeInfoSender(contentId);
		expect(stakeInfoSender.token).equal(erc20.address);
		expect(stakeInfoSender.sender).equal(user2.address);
		expect(stakeInfoSender.stakeBlockedUntil).equal(lockupPeriod.add(timestamp));
		expect(stakeInfoSender.canceled).to.be.false;

		const stakeInfoRecipient = await configFacet.contentIdToRecipientToStakeInfo(contentId, user1.address);
		expect(stakeInfoRecipient.amount).equal(100);
		expect(stakeInfoRecipient.claimed).to.be.false;
	});

	it('should send bulk mail overriding default pay for attention with custom', async () => {
		const configFacet = await ethers.getContractAt('ConfigFacet', diamondAddress);
		const mailerFacet = await ethers.getContractAt('MailerFacet', diamondAddress);

		await configFacet.connect(user1).setPaywall([{ token: erc20.address, amount: 200 }]);

		expect(await configFacet.recipientToPaywallTokenToAmount(user1.address, erc20.address)).equal(200);

		expect(await configFacet.allowedTokens()).deep.equal([erc20_2.address, erc20.address]);
		expect(await configFacet.defaultPaywallTokenToAmount(erc20.address)).equal(100);
		expect(await configFacet.defaultPaywallTokenToAmount(erc20_2.address)).equal(0);
		expect(await configFacet.isAllowedToken(erc20.address)).equal(true);
		expect(await configFacet.isAllowedToken(erc20_2.address)).equal(true);
		const user2PaywallInfo = await configFacet.getRecipientPaywallInfo(user1.address, user2.address);
		expect(user2PaywallInfo[0].token).equal(erc20_2.address);
		expect(user2PaywallInfo[0].amount).equal(0);
		expect(user2PaywallInfo[1].token).equal(erc20.address);
		expect(user2PaywallInfo[1].amount).equal(220);

		await erc20.connect(user2).mint(1100);
		const user2Balance = await erc20.balanceOf(user2.address);
		await erc20.connect(user2).approve(diamondAddress, 1100);
		expect(await erc20.balanceOf(user1.address)).equal(1100);
		const recKeySups = [
			{
				recipient: user1.address,
				key: '0x0102',
				supplement: '0x',
			},
		];
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		await mailerFacet.connect(user2).sendBulkMail(feedId, 123, recKeySups, erc20.address, content);
		expect(await erc20.balanceOf(user2.address)).equal(user2Balance.sub(220));
		expect(await erc20.balanceOf(user1.address)).equal(1100);

		const currentBlock = await ethers.provider.getBlockNumber();
		const mailEvents = await mailerFacet.queryFilter(mailerFacet.filters.MailPush(null, feedId), currentBlock + 1);
		let contentId = BigNumber.from(0);
		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user2.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);
			if (mailEvents[i].args.recipient.eq(user1.address)) {
				contentId = mailEvents[i].args.contentId;
			}
		}

		const timestamp = await ethers.provider.getBlock(currentBlock).then(block => block.timestamp);

		const lockupPeriod = await configFacet.stakeLockUpPeriod();

		const stakeInfoSender = await configFacet.contentIdToStakeInfoSender(contentId);
		expect(stakeInfoSender.token).equal(erc20.address);
		expect(stakeInfoSender.sender).equal(user2.address);
		expect(stakeInfoSender.stakeBlockedUntil).equal(lockupPeriod.add(timestamp));
		expect(stakeInfoSender.canceled).to.be.false;

		const stakeInfoRecipient = await configFacet.contentIdToRecipientToStakeInfo(contentId, user1.address);
		expect(stakeInfoRecipient.amount).equal(200);
		expect(stakeInfoRecipient.claimed).to.be.false;
	});

	it('getRecipientsPaywallByToken', async () => {
		const configFacet = await ethers.getContractAt('ConfigFacet', diamondAddress);
		expect(
			await configFacet.getRecipientsPaywallByToken([user2.address, user1.address], owner.address, erc20.address),
		).deep.equal([1100, 220]);
	});

	it('should send bulk mail overriding default pay for attention with custom', async () => {
		const mailerFacet = await ethers.getContractAt('MailerFacet', diamondAddress);
		await erc20.connect(user2).mint('1000000000000000000000000');
		await erc20.connect(user2).approve(diamondAddress, '100000000000000000000000000');
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		await mailerFacet.connect(user2).sendBulkMail(
			feedId,
			123,
			new Array(100).fill({}).map(_ => ({
				recipient: ethers.Wallet.createRandom().address,
				key: '0x0102',
				supplement: '0x',
			})),
			erc20.address,
			content,
		);
	});
});
