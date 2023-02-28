import { ethers } from "hardhat";
import { YlideMailerV8 } from "../typechain-types";

async function main() {
    const YlideMailerV8 = await ethers.getContractFactory("YlideMailerV8");
    const YlideRegistryV6 = await ethers.getContractFactory("YlideRegistryV6");
    const mailer = await YlideMailerV8.deploy();
    const registry = await YlideRegistryV6.deploy();

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
