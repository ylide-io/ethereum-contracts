import { ethers } from 'hardhat';
import { FacetCut, FacetCutAction } from '../scripts/types';
import { getSelectors } from '../scripts/utils';

const meAddress = '0x94ceF219229d6C371D9212AD97D2c831B4E8C380';
const me2Address = '0xD64cCa07f97Ff3e4C06118accF70B32482445d7c';
const me3Address = '0xdC5047dC210bC608fF1a6892A77301dCD0844966';
const me4Address = '0x305705398b1Dd9CeF22D4b9d0F362715d1E3d4d3';

const referrerPk = '0x5294e9364c1751fa20f742fd0145e56e60150061fe31eb177c3366418e3bc572';
const referrerAddress = '0xD1c197F52A676063ED6E10EA0a91b44c44A4021D';

(async () => {
	const [owner] = await ethers.getSigners();

	// deploy DiamondCutFacet
	const DiamondCutFacet = await ethers.getContractFactory('DiamondCutFacet', owner);
	const diamondCutFacet = await DiamondCutFacet.deploy();
	await diamondCutFacet.deployed();

	// deploy Diamond
	const Diamond = await ethers.getContractFactory('Ylide', owner);
	const diamond = await Diamond.deploy(owner.address, diamondCutFacet.address);
	await diamond.deployed();

	// deploy facets
	const FacetNames = ['DiamondLoupeFacet', 'ConfigFacet', 'MailerFacet', 'RegistryFacet', 'StakeFacet'];
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
	await owner.sendTransaction({ to: meAddress, value: ethers.utils.parseEther('1') });
	console.log('Owner address: ' + owner.address);
	console.log('Ylide Diamond address: ' + diamond.address);
	const erc20 = await ethers.getContractFactory('MockERC20', owner).then(f => f.deploy('mock', 'token'));
	await erc20.deployed();
	await erc20.mintTo(meAddress, ethers.utils.parseEther('1000'));
	console.log('MockERC20: ' + erc20.address);
	const mailerFacet = await ethers.getContractAt('MailerFacet', diamond.address);
	const tx = await mailerFacet.connect(owner).createMailingFeed('768768768768121341');
	const receipt = await tx.wait();
	console.log('Feed id: ' + String(receipt.events?.[0].args?.[0] || 0));
	await owner.sendTransaction({ to: me2Address, value: ethers.utils.parseEther('1') });

	const erc20_2 = await ethers.getContractFactory('MockERC20', owner).then(f => f.deploy('mock', 'token2'));
	await erc20_2.deployed();
	await erc20_2.mintTo(meAddress, ethers.utils.parseEther('1000'));
	console.log('MockERC20: ' + erc20_2.address);
	const configFacet = await ethers.getContractAt('ConfigFacet', diamond.address);
	await configFacet.connect(owner).addAllowedTokens([erc20.address, erc20_2.address]);
	await configFacet.connect(owner).setPaywallDefault([
		{ token: erc20.address, amount: ethers.utils.parseEther('5') },
		{ token: erc20_2.address, amount: ethers.utils.parseEther('10') },
	]);

	await configFacet.connect(owner).setStakeLockUpPeriod(100);
	// 4% ylide commission
	await configFacet.connect(owner).setYlideCommissionPercentage(400);
	// 6% referrer commission
	const referrer = new ethers.Wallet(referrerPk, ethers.provider);
	await owner.sendTransaction({ to: referrer.address, value: ethers.utils.parseEther('1') });
	await configFacet.connect(referrer).setRegistrarToCommissionPercentage(600);
	await owner.sendTransaction({
		to: '0xdC5047dC210bC608fF1a6892A77301dCD0844966',
		value: ethers.utils.parseEther('1'),
	});
})();
