import { ethers } from "hardhat";
import { YlideMailerV8 } from "../typechain-types";

async function main() {
    const YlideMailerV8 = await ethers.getContractFactory("YlideMailerV8");
    const YlideRegistryV5 = await ethers.getContractFactory("YlideRegistryV5");
    const mailer = await YlideMailerV8.deploy();
    const registry = await YlideRegistryV5.deploy(
        "0x0000000000000000000000000000000000000000"
    );

    await mailer.deployed();
    await registry.deployed();

    console.log("Mailer address:", mailer.address);
    console.log("Registry address:", registry.address);

    const contentId = await (mailer as YlideMailerV8).functions.buildContentId(
        "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
        123,
        321,
        3,
        600
    );
    console.log("contentId: ", contentId);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
