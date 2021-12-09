const hre = require("hardhat");

const config = require("../config.js");
const utils = require("./utils");

async function main() {
    const [deployer] = await ethers.getSigners();

    await utils.deployAndVerify("FundsHolder", []);

    /* await utils.deployAndVerify("ExilonNftLootbox", [
        "",
        "0x99964c0fb8098f513e4ed88629ec53b674d69c41", // EXILON Testnet
        "0x916082868d33a860C297F4c54Ac18771186ed73c", // USD Testnet
        "0xCc7aDc94F3D80127849D2b41b6439b7CF1eB4Ae0", // Dex Router Testnet
        "0x89A6f0C27Bc71B5768e4Cd01B8FaDBB4205ff1E1" // Master contract Testnet
    ]); */

    //await utils.deployAndVerify("ERC1155Test", []);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
