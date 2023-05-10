import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import { FacetCut, FacetCutAction } from '../scripts/types';
import { getSelectors } from '../scripts/utils';
import { BigNumber } from 'ethers';

describe('Diamond', () => {
	let owner: SignerWithAddress;
	let user1: SignerWithAddress;
	let user2: SignerWithAddress;
	let diamondAddress: string;

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
		const FacetNames = ['DiamondLoupeFacet', 'OwnershipFacet', 'ConfigFacet', 'MailerFacet', 'RegistryFacet'];
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

	it('should add key to registry', async () => {
		const registryFacet = await ethers.getContractAt('RegistryFacet', diamondAddress);
		await registryFacet.connect(user1).attachPublicKey(BigNumber.from(ethers.utils.randomBytes(32)), 1, 123);
	});
});
