const hre = require("hardhat");

const config = require("../config.js");
const utils = require("./utils");

async function main() {
    const [deployer] = await ethers.getSigners();

    const ExilonNftLootboxLibraryFactory = await hre.ethers.getContractFactory("ExilonNftLootboxLibrary");
    const ExilonNftLootboxLibraryInst = await ExilonNftLootboxLibraryFactory.deploy();
    await ExilonNftLootboxLibraryInst.deployed();
    await hre.run("verify:verify", {
        address: ExilonNftLootboxLibraryInst.address
    });

    const ExilonNftLootboxFactory = await hre.ethers.getContractFactory("ExilonNftLootbox", {
        libraries: {
            ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
        }
    });
    const ExilonNftLootboxInst = await ExilonNftLootboxFactory.deploy(
        "0x99964c0fb8098f513e4ed88629ec53b674d69c41", // EXILON Testnet
        "0x916082868d33a860C297F4c54Ac18771186ed73c", // USD Testnet
    );
    await ExilonNftLootboxInst.deployed();
    await hre.run("verify:verify", {
        address: ExilonNftLootboxInst.address,
        constructorArguments: [
            "0x99964c0fb8098f513e4ed88629ec53b674d69c41", // EXILON Testnet
            "0x916082868d33a860C297F4c54Ac18771186ed73c", // USD Testnet
        ]
    });

    await hre.run("verify:verify", {
        address: await ExilonNftLootboxInst.masterContract(),
        libraries: {
            ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
        }
    });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
