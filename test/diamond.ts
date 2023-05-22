import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { FacetCut, FacetCutAction } from '../scripts/types';
import { getSelectors, mine } from '../scripts/utils';
import { MockERC20 } from '../typechain-types';

describe('Diamond', () => {
	let owner: SignerWithAddress;
	let user1: SignerWithAddress;
	let user2: SignerWithAddress;
	let registrar: SignerWithAddress;
	let referrerInterface: SignerWithAddress;
	let erc20: MockERC20;
	let erc20_2: MockERC20;
	let diamondAddress: string;
	let feedId: string;

	before(async () => {
		[owner, user1, user2, registrar, referrerInterface] = await ethers.getSigners();
	});

	it('should deploy diamond and facets', async () => {
		erc20 = await ethers.getContractFactory('MockERC20', owner).then(f => f.deploy('mock', 'token'));
		erc20_2 = await ethers.getContractFactory('MockERC20', owner).then(f => f.deploy('mock', 'token'));
		// deploy DiamondCutFacet
		const DiamondCutFacet = await ethers.getContractFactory('DiamondCutFacet', owner);
		const diamondCutFacet = await DiamondCutFacet.deploy();
		await diamondCutFacet.deployed();

		// deploy Diamond
		const Diamond = await ethers.getContractFactory('YlideDiamond', owner);
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
		const diamondCut = await ethers.getContractAt('IDiamondCut', diamond.address);
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
		const diamondCut = await ethers.getContractAt('IDiamondCut', diamondAddress);
		await diamondCut.diamondCut(
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
		const publicKey = BigNumber.from(ethers.utils.randomBytes(32));
		const keyVersion = 1;
		await registryFacet.connect(user1).attachPublicKey(publicKey, keyVersion, registrar.address);
		await registryFacet.connect(user2).attachPublicKey(publicKey, keyVersion, registrar.address);
		const registryInfo = await configFacet.addressToPublicKey(user1.address);
		expect(registryInfo.publicKey).equal(publicKey);
		expect(registryInfo.keyVersion).equal(keyVersion);
		expect(registryInfo.registrar).equal(registrar.address);
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
				recipient: BigNumber.from(user2.address),
				token: ethers.constants.AddressZero,
				key: '0x0102',
				supplement: '0x',
			},
			{
				recipient: BigNumber.from(owner.address),
				token: ethers.constants.AddressZero,
				key: '0x010203',
				supplement: '0x',
			},
		];
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		const mailerFacet = await ethers.getContractAt('MailerFacet', diamondAddress);
		await mailerFacet.connect(user1).sendBulkMail(feedId, 123, recKeySups, content);
		const mailEvents = await mailerFacet.queryFilter(mailerFacet.filters.MailPush(null, feedId));

		for (let i = 0; i < mailEvents.length; i++) {
			expect(mailEvents[i].args.feedId).equal(feedId);
			expect(mailEvents[i].args.sender).equal(user1.address);
			expect(mailEvents[i].args.recipient).equal(recKeySups[i].recipient);
			expect(mailEvents[i].args.key).equal(recKeySups[i].key);
			expect(mailEvents[i].args.supplement).equal(recKeySups[i].supplement);
		}
	});

	it('should add mail recipients', async () => {
		const recKeySups = [
			{
				recipient: BigNumber.from(user2.address),
				token: ethers.constants.AddressZero,
				key: '0x0102',
				supplement: '0x',
			},
			{
				recipient: BigNumber.from(owner.address),
				token: ethers.constants.AddressZero,
				key: '0x010203',
				supplement: '0x',
			},
		];
		const mailerFacet = await ethers.getContractAt('MailerFacet', diamondAddress);

		const currentBlock = await ethers.provider.getBlockNumber();
		await mailerFacet.connect(user1).addMailRecipients(feedId, 123, recKeySups, currentBlock, 20, 200);
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

		await configFacet
			.connect(owner)
			.addAllowedTokens([user2.address, erc20.address, owner.address, erc20_2.address]);
		expect(await configFacet.allowedTokens()).deep.equal([
			user2.address,
			erc20.address,
			owner.address,
			erc20_2.address,
		]);

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

		await configFacet.connect(owner).removeAllowedTokens([user2.address, owner.address]);
		expect(await configFacet.allowedTokens()).deep.equal([erc20_2.address, erc20.address]);
	});

	it('should correctly set fees for pay for attention', async () => {
		const configFacet = await ethers.getContractAt('ConfigFacet', diamondAddress);
		await configFacet.connect(owner).setStakeLockUpPeriod(100);
		// 4% ylide commission
		await configFacet.connect(owner).setYlideCommissionPercentage(400);
		// 6% registrar commission
		await configFacet.connect(registrar).setRegistrarToCommissionPercentage(600);

		expect(await configFacet.stakeLockUpPeriod()).equal(100);
		expect(await configFacet.ylideCommissionPercentage()).equal(400);
		expect(await configFacet.registrarToCommissionPercentage(registrar.address)).equal(600);
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
				recipient: BigNumber.from(user2.address),
				token: erc20.address,
				key: '0x0102',
				supplement: '0x',
			},
			{
				recipient: BigNumber.from(owner.address),
				token: erc20.address,
				key: '0x010203',
				supplement: '0x',
			},
		];
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		await mailerFacet.connect(user1).sendBulkMail(feedId, 123, recKeySups, content);
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
			if (mailEvents[i].args.recipient.eq(BigNumber.from(user2.address))) {
				contentId = mailEvents[i].args.contentId;
			}
		}

		const timestamp = await ethers.provider.getBlock(currentBlock).then(block => block.timestamp);

		const lockupPeriod = await configFacet.stakeLockUpPeriod();

		const stakeInfo = await configFacet.contentIdToRecipientToTokenInfo(contentId, user2.address);
		expect(stakeInfo.amount).equal(1000);
		expect(stakeInfo.token).equal(erc20.address);
		expect(stakeInfo.withdrawn).equal(false);
		expect(stakeInfo.stakeBlockedUntil).equal(lockupPeriod.add(timestamp));
		expect(stakeInfo.ylideCommission).equal(40);
		expect(stakeInfo.registrarCommission).equal(60);

		await expect(
			stakeFacet.connect(user1).cancel([{ contentId: contentId, recipient: owner.address }]),
		).to.be.revertedWithCustomError(stakeFacet, 'NothingToWithdraw');
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
		expect(await erc20.balanceOf(user1.address)).equal(1100);
		expect(await erc20.balanceOf(user2.address)).equal(0);
		expect(await erc20.balanceOf(diamondAddress)).equal(0);

		const stakeInfoAfter = await configFacet.contentIdToRecipientToTokenInfo(contentId, user2.address);
		expect(stakeInfoAfter.amount).equal(1000);
		expect(stakeInfoAfter.token).equal(erc20.address);
		expect(stakeInfoAfter.withdrawn).equal(true);
		expect(stakeInfoAfter.stakeBlockedUntil).equal(lockupPeriod.add(timestamp));
		expect(stakeInfoAfter.ylideCommission).equal(40);
		expect(stakeInfoAfter.registrarCommission).equal(60);
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
				recipient: BigNumber.from(user2.address),
				token: erc20.address,
				key: '0x0102',
				supplement: '0x',
			},
			{
				recipient: BigNumber.from(owner.address),
				token: erc20.address,
				key: '0x010203',
				supplement: '0x',
			},
		];
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		await mailerFacet.connect(user1).sendBulkMail(feedId, 123, recKeySups, content);
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
			if (mailEvents[i].args.recipient.eq(BigNumber.from(user2.address))) {
				contentId = mailEvents[i].args.contentId;
			}
		}

		const timestamp = await ethers.provider.getBlock(currentBlock).then(block => block.timestamp);

		const lockupPeriod = await configFacet.stakeLockUpPeriod();

		const stakeInfo = await configFacet.contentIdToRecipientToTokenInfo(contentId, user2.address);
		expect(stakeInfo.amount).equal(1000);
		expect(stakeInfo.token).equal(erc20.address);
		expect(stakeInfo.withdrawn).equal(false);
		expect(stakeInfo.stakeBlockedUntil).equal(lockupPeriod.add(timestamp));
		expect(stakeInfo.ylideCommission).equal(40);
		expect(stakeInfo.registrarCommission).equal(60);

		await expect(
			stakeFacet.connect(owner)['claim(uint256[],(address,uint256))']([contentId], {
				interfaceAddress: referrerInterface.address,
				// 40% interface commission
				interfaceCommission: 4000,
			}),
		).to.be.revertedWithCustomError(stakeFacet, 'NoRegistrar');

		await expect(
			stakeFacet.connect(user2)['claim(uint256[],(address,uint256))']([contentId.add(1)], {
				interfaceAddress: referrerInterface.address,
				// 40% interface commission
				interfaceCommission: 4000,
			}),
		).to.be.revertedWithCustomError(stakeFacet, 'NothingToWithdraw');

		await stakeFacet.connect(user2)['claim(uint256[],(address,uint256))']([contentId], {
			interfaceAddress: referrerInterface.address,
			// 40% interface commission
			interfaceCommission: 4000,
		});

		await expect(
			stakeFacet.connect(user2)['claim(uint256[],(address,uint256))']([contentId], {
				interfaceAddress: referrerInterface.address,
				// 40% interface commission
				interfaceCommission: 4000,
			}),
		).to.be.revertedWithCustomError(stakeFacet, 'NothingToWithdraw');

		expect(await erc20.balanceOf(user2.address)).equal(600);
		expect(await erc20.balanceOf(diamondAddress)).equal(500);
		expect(await configFacet.addressToTokenToAmount(referrerInterface.address, erc20.address)).equal(400);
		expect(await configFacet.addressToTokenToAmount(owner.address, erc20.address)).equal(40);
		expect(await configFacet.addressToTokenToAmount(registrar.address, erc20.address)).equal(60);

		await stakeFacet.connect(referrerInterface)['claim(address)'](erc20.address);
		await stakeFacet.connect(owner)['claim(address)'](erc20.address);
		await stakeFacet.connect(registrar)['claim(address)'](erc20.address);

		await expect(
			stakeFacet.connect(referrerInterface)['claim(address)'](erc20.address),
		).to.be.revertedWithCustomError(stakeFacet, 'NothingToWithdraw');
		await expect(stakeFacet.connect(owner)['claim(address)'](erc20.address)).to.be.revertedWithCustomError(
			stakeFacet,
			'NothingToWithdraw',
		);
		await expect(stakeFacet.connect(registrar)['claim(address)'](erc20.address)).to.be.revertedWithCustomError(
			stakeFacet,
			'NothingToWithdraw',
		);

		expect(await configFacet.addressToTokenToAmount(referrerInterface.address, erc20.address)).equal(0);
		expect(await configFacet.addressToTokenToAmount(owner.address, erc20.address)).equal(0);
		expect(await configFacet.addressToTokenToAmount(registrar.address, erc20.address)).equal(0);

		expect(await erc20.balanceOf(diamondAddress)).equal(0);
		expect(await erc20.balanceOf(referrerInterface.address)).equal(400);
		expect(await erc20.balanceOf(owner.address)).equal(40);
		expect(await erc20.balanceOf(registrar.address)).equal(60);
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
				recipient: BigNumber.from(user2.address),
				token: erc20.address,
				key: '0x0102',
				supplement: '0x',
			},
			{
				recipient: BigNumber.from(owner.address),
				token: erc20.address,
				key: '0x010203',
				supplement: '0x',
			},
		];
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		await mailerFacet.connect(user1).sendBulkMail(feedId, 123, recKeySups, content);
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
			if (mailEvents[i].args.recipient.eq(BigNumber.from(user2.address))) {
				contentId = mailEvents[i].args.contentId;
			}
		}

		const stakeInfo = await configFacet.contentIdToRecipientToTokenInfo(contentId, user2.address);
		expect(stakeInfo.amount).equal(0);
		expect(stakeInfo.token).equal(ethers.constants.AddressZero);
		expect(stakeInfo.withdrawn).equal(false);
		expect(stakeInfo.stakeBlockedUntil).equal(0);
		expect(stakeInfo.ylideCommission).equal(0);
		expect(stakeInfo.registrarCommission).equal(0);

		await expect(
			stakeFacet.connect(user2)['claim(uint256[],(address,uint256))']([contentId], {
				interfaceAddress: referrerInterface.address,
				// 40% interface commission
				interfaceCommission: 4000,
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
				recipient: BigNumber.from(user1.address),
				token: erc20.address,
				key: '0x0102',
				supplement: '0x',
			},
		];
		await mailerFacet.connect(user2).sendBulkMail(feedId, 123, recKeySups, content);
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
			if (mailEvents[i].args.recipient.eq(BigNumber.from(user1.address))) {
				contentId = mailEvents[i].args.contentId;
			}
		}

		const timestamp = await ethers.provider.getBlock(currentBlock).then(block => block.timestamp);

		const lockupPeriod = await configFacet.stakeLockUpPeriod();

		const stakeInfo = await configFacet.contentIdToRecipientToTokenInfo(contentId, user1.address);
		expect(stakeInfo.amount).equal(100);
		expect(stakeInfo.token).equal(erc20.address);
		expect(stakeInfo.withdrawn).equal(false);
		expect(stakeInfo.stakeBlockedUntil).equal(lockupPeriod.add(timestamp));
		expect(stakeInfo.ylideCommission).equal(4);
		expect(stakeInfo.registrarCommission).equal(6);
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
				recipient: BigNumber.from(user1.address),
				token: erc20.address,
				key: '0x0102',
				supplement: '0x',
			},
		];
		const content = new Uint8Array([8, 7, 8, 7, 8, 7]);
		await mailerFacet.connect(user2).sendBulkMail(feedId, 123, recKeySups, content);
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
			if (mailEvents[i].args.recipient.eq(BigNumber.from(user1.address))) {
				contentId = mailEvents[i].args.contentId;
			}
		}

		const timestamp = await ethers.provider.getBlock(currentBlock).then(block => block.timestamp);

		const lockupPeriod = await configFacet.stakeLockUpPeriod();

		const stakeInfo = await configFacet.contentIdToRecipientToTokenInfo(contentId, user1.address);
		expect(stakeInfo.amount).equal(200);
		expect(stakeInfo.token).equal(erc20.address);
		expect(stakeInfo.withdrawn).equal(false);
		expect(stakeInfo.stakeBlockedUntil).equal(lockupPeriod.add(timestamp));
		expect(stakeInfo.ylideCommission).equal(8);
		expect(stakeInfo.registrarCommission).equal(12);
	});
});
