import { ethers } from "hardhat";

async function main() {
    const YlideMailerV4 = await ethers.getContractFactory("YlideMailerV4");
    const YlideRegistryV1 = await ethers.getContractFactory("YlideRegistryV1");
    const mailer = await YlideMailerV4.deploy();
    const registry = await YlideRegistryV1.deploy();

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
