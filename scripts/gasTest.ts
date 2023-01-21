import { ethers } from "hardhat";
import { YlideMailerV8, YlideRegistryV5 } from "../typechain-types";
import fs from "fs";

const prevResults = fs.existsSync("./gasTestResults.json")
    ? JSON.parse(fs.readFileSync("./gasTestResults.json", "utf8"))
    : null;

const currResults: Record<string, number> = {};

function printResult(name: string, value: number) {
    currResults[name] = value;
    if (prevResults && prevResults[name]) {
        const sign = value > prevResults[name] ? "+" : "";
        const val = value - prevResults[name];
        console.log(`${name}: ${value} (${sign}${val})`);
    } else {
        console.log(`${name}: ${value}`);
    }
}

async function main() {
    const ylideMailerV8 = await ethers.getContractFactory("YlideMailerV8");
    const ylideRegistryV5 = await ethers.getContractFactory("YlideRegistryV5");

    const mailer = (await ylideMailerV8.deploy()) as YlideMailerV8;
    const registry = (await ylideRegistryV5.deploy(
        "0x0000000000000000000000000000000000000000"
    )) as YlideRegistryV5;

    await mailer.deployed();
    await registry.deployed();

    const storeBlockNumberGasCost = await mailer.estimateGas.storeBlockNumber(
        0,
        12345
    );
    const senderAddress = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
    const buildHashGasCost = await mailer.estimateGas.buildHash(
        senderAddress,
        "0x00",
        "0x00"
    );
    const initTime = Math.floor(Date.now() / 1000);
    const uniqueId = 12345;
    const msgId = await mailer.functions.buildHash(
        senderAddress,
        uniqueId,
        initTime
    );
    const sendSmallMailGasCost = await mailer.estimateGas.sendSmallMail(
        uniqueId,
        "0x0000000000000000000000000000000000000000",
        "0x00",
        "0x00"
    );
    const sendBulkMailGasCost = await mailer.estimateGas.sendBulkMail(
        uniqueId,
        ["0x0000000000000000000000000000000000000000"],
        ["0x00"],
        "0x00"
    );
    const sendMultipartPartGasCost = await mailer.estimateGas.sendMultipartPart(
        uniqueId,
        initTime,
        1,
        0,
        "0x00"
    );
    const addMailRecipientsGasCost = await mailer.estimateGas.addMailRecipients(
        uniqueId,
        initTime,
        ["0x0000000000000000000000000000000000000000"],
        ["0x00"]
    );
    const sendBroadcastGasCost = await mailer.estimateGas.sendBroadcast(
        uniqueId,
        "0x00"
    );
    const sendBroadcastHeaderGasCost =
        await mailer.estimateGas.sendBroadcastHeader(uniqueId, initTime);

    console.log("--------- BlockNumberRingBufferIndex costs ---------");
    printResult("storeBlockNumber", storeBlockNumberGasCost.toNumber());
    console.log("--------------------------------");
    console.log("--------- Mailer costs ---------");
    printResult("buildHash", buildHashGasCost.toNumber());
    printResult("sendMultipartPart", sendMultipartPartGasCost.toNumber());
    printResult("addMailRecipients", addMailRecipientsGasCost.toNumber());
    printResult("sendSmallMail", sendSmallMailGasCost.toNumber());
    printResult("sendBulkMail", sendBulkMailGasCost.toNumber());
    printResult("sendBroadcast", sendBroadcastGasCost.toNumber());
    printResult("sendBroadcastHeader", sendBroadcastHeaderGasCost.toNumber());
    console.log("--------------------------------");

    fs.writeFileSync(
        "./gasTestResults.json",
        JSON.stringify(currResults),
        "utf-8"
    );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
