import { ethers } from "hardhat";

async function main() {
    const YlideMailerV6 = await ethers.getContractFactory("YlideMailerV6");
    const YlideRegistryV3 = await ethers.getContractFactory("YlideRegistryV3");
    const mailer = await YlideMailerV6.deploy();
    const registry = await YlideRegistryV3.deploy(
        "0x0000000000000000000000000000000000000000"
    );

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
