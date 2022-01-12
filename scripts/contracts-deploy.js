const hre = require("hardhat");

const config = require("../config.json");

async function main() {
    if (hre.network.name != "bscTestnet" && hre.network.name != "bscMainnet") {
        console.log("Wrong network");
        return;
    }

    const [deployer] = await ethers.getSigners();

    let exilonAddress;
    let usdAddress;
    let dexRouterAddress;
    if (hre.network.name == "bscTestnet") {
        exilonAddress = config.exilonAddressTestnet;
        usdAddress = config.usdAddressTestnet;
        dexRouterAddress = config.dexRouterTestnet;
    } else {
        exilonAddress = config.exilonAddressMainnet;
        usdAddress = config.usdAddressMainnet;
        dexRouterAddress = config.dexRouterMainnet;
    }

    const FeeReceiverFactory = await hre.ethers.getContractFactory("FeeReceiver");
    FeeReceiverInst = await FeeReceiverFactory.deploy(
        config.feeReceivers,
        config.feeReceiverAmounts
    );

    const ExilonNftLootboxLibraryFactory = await hre.ethers.getContractFactory(
        "ExilonNftLootboxLibrary"
    );
    console.log("Deploying ExilonNftLootboxLibrary...");
    const ExilonNftLootboxLibraryInst = await ExilonNftLootboxLibraryFactory.deploy();
    await ExilonNftLootboxLibraryInst.deployed();
    await hre.run("verify:verify", {
        address: ExilonNftLootboxLibraryInst.address,
    });

    const ExilonNftLootboxMainFactory = await hre.ethers.getContractFactory(
        "ExilonNftLootboxMain"
    );
    console.log("Deploying ExilonNftLootboxMain...");
    const ExilonNftLootboxMainInst = await ExilonNftLootboxMainFactory.deploy();
    await ExilonNftLootboxMainInst.deployed();
    await hre.run("verify:verify", {
        address: ExilonNftLootboxMainInst.address,
    });

    const ExilonNftLootboxMasterFactory = await hre.ethers.getContractFactory("ExilonNftLootboxMaster", {
        libraries: {
            ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
        },
    });
    let arguments = [exilonAddress, usdAddress, dexRouterAddress, FeeReceiverInst.address];
    console.log("Deploying ExilonNftLootboxMaster...");
    const ExilonNftLootboxMasterInst = await ExilonNftLootboxMasterFactory.deploy(...arguments);
    await ExilonNftLootboxMasterInst.deployed();
    await hre.run("verify:verify", {
        address: ExilonNftLootboxMasterInst.address,
        constructorArguments: arguments,
    });

    /* await hre.run("verify:verify", {
        address: await ExilonNftLootboxInst.masterContract(),
        libraries: {
            ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
        }
    }); */

    const ERC721MainFactory = await hre.ethers.getContractFactory("ERC721Main");
    arguments = [usdAddress, dexRouterAddress, FeeReceiverInst.address];
    console.log("Deploying ERC721Main...");
    const ERC721MainInst = await ERC721MainFactory.deploy(...arguments);
    await ERC721MainInst.deployed();
    await hre.run("verify:verify", {
        address: ERC721MainInst.address,
        constructorArguments: arguments,
    });

    const ERC1155MainFactory = await hre.ethers.getContractFactory("ERC1155Main");
    console.log("Deploying ERC1155Main...");
    const ERC1155MainInst = await ERC1155MainFactory.deploy(...arguments);
    await ERC1155MainInst.deployed();
    await hre.run("verify:verify", {
        address: ERC1155MainInst.address,
        constructorArguments: arguments,
    });

    const NftMarketplaceFactory = await hre.ethers.getContractFactory("NftMarketplace", {
        libraries: {
            ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
        },
    });
    console.log("Deploying NftMarketplace...");
    const NftMarketplaceInst = await NftMarketplaceFactory.deploy(...arguments);
    await NftMarketplaceInst.deployed();
    await hre.run("verify:verify", {
        address: NftMarketplaceInst.address,
        constructorArguments: arguments,
    });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
