import { ethers } from "hardhat";

async function main() {
    const YlideMailerV5 = await ethers.getContractFactory("YlideMailerV5");
    const YlideRegistryV2 = await ethers.getContractFactory("YlideRegistryV2");
    const mailer = await YlideMailerV5.deploy();
    const registry = await YlideRegistryV2.deploy();

    await mailer.deployed();
    await registry.deployed();

    console.log("Mailer address:", mailer.address);
    console.log("Registry address:", registry.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
