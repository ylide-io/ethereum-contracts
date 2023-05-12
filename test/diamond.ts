import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { FacetCut, FacetCutAction } from '../scripts/types';
import { getSelectors } from '../scripts/utils';

describe('Diamond', () => {
	let owner: SignerWithAddress;
	let user1: SignerWithAddress;
	let user2: SignerWithAddress;
	let diamondAddress: string;
	let feedId: string;

	before(async () => {
		[owner, user1, user2] = await ethers.getSigners();
	});

	it('should deploy diamond and facets', async () => {
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
		const FacetNames = ['DiamondLoupeFacet', 'ConfigFacet', 'MockMailerFacet', 'RegistryFacet'];
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
		const registrar = 123;
		await registryFacet.connect(user1).attachPublicKey(publicKey, keyVersion, registrar);
		const registryInfo = await configFacet.addressToPublicKey(user1.address);
		expect(registryInfo.publicKey).equal(publicKey);
		expect(registryInfo.keyVersion).equal(keyVersion);
		expect(registryInfo.registrar).equal(registrar);
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
});
