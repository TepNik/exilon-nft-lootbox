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

    const AccessFactory = await hre.ethers.getContractFactory("Access");
    console.log("Deploying Access...");
    const AccessInst = await AccessFactory.deploy();
    await AccessInst.deployed();
    console.log("Access deployed at", AccessInst.address);
    try {
        await hre.run("verify:verify", {
            address: AccessInst.address,
        });
    } catch (error) {
        console.log("Error =", error);
    }

    const FeeReceiverFactory = await hre.ethers.getContractFactory("FeeReceiver");
    let arguments = [config.feeReceivers, config.feeReceiverAmounts];
    console.log("Deploying FeeReceiver...");
    const FeeReceiverInst = await FeeReceiverFactory.deploy(...arguments);
    await FeeReceiverInst.deployed();
    console.log("FeeReceiver deployed at", FeeReceiverInst.address);
    try {
        await hre.run("verify:verify", {
            address: FeeReceiverInst.address,
            constructorArguments: arguments,
        });
    } catch (error) {
        console.log("Error =", error);
    }

    const ExilonNftLootboxLibraryFactory = await hre.ethers.getContractFactory(
        "ExilonNftLootboxLibrary"
    );
    console.log("Deploying ExilonNftLootboxLibrary...");
    const ExilonNftLootboxLibraryInst = await ExilonNftLootboxLibraryFactory.deploy();
    await ExilonNftLootboxLibraryInst.deployed();
    console.log("ExilonNftLootboxLibrary deployed at", ExilonNftLootboxLibraryInst.address);
    try {
        await hre.run("verify:verify", {
            address: ExilonNftLootboxLibraryInst.address,
        });
    } catch (error) {
        console.log("Error =", error);
    }

    const NftMarketplaceFactory = await hre.ethers.getContractFactory("NftMarketplace", {
        libraries: {
            ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
        },
    });
    arguments = [usdAddress, dexRouterAddress, FeeReceiverInst.address, AccessInst.address];
    console.log("Deploying NftMarketplace...");
    const NftMarketplaceInst = await NftMarketplaceFactory.deploy(...arguments);
    await NftMarketplaceInst.deployed();
    console.log("NftMarketplace deployed at", NftMarketplaceInst.address);
    try {
        await hre.run("verify:verify", {
            address: NftMarketplaceInst.address,
            constructorArguments: arguments,
        });
    } catch (error) {
        console.log("Error =", error);
    }

    const ExilonNftLootboxMainFactory = await hre.ethers.getContractFactory(
        "ExilonNftLootboxMain",
        {
            libraries: {
                ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
            },
        }
    );
    arguments = [
        NftMarketplaceInst.address,
        usdAddress,
        dexRouterAddress,
        FeeReceiverInst.address,
        AccessInst.address,
    ];
    console.log("Deploying ExilonNftLootboxMain...");
    const ExilonNftLootboxMainInst = await ExilonNftLootboxMainFactory.deploy(...arguments);
    await ExilonNftLootboxMainInst.deployed();
    console.log("ExilonNftLootboxMain deployed at", ExilonNftLootboxMainInst.address);
    try {
        await hre.run("verify:verify", {
            address: ExilonNftLootboxMainInst.address,
            constructorArguments: arguments,
        });
    } catch (error) {
        console.log("Error =", error);
    }

    const FundsHolderFactoryFactory = await hre.ethers.getContractFactory("FundsHolderFactory");
    console.log("Deploying FundsHolderFactory...");
    const FundsHolderFactoryInst = await FundsHolderFactoryFactory.deploy();
    await FundsHolderFactoryInst.deployed();
    console.log("FundsHolderFactory deployed at", FundsHolderFactoryInst.address);
    try {
        await hre.run("verify:verify", {
            address: FundsHolderFactoryInst.address,
        });
    } catch (error) {
        console.log("Error =", error);
    }

    const ExilonNftLootboxMasterFactory = await hre.ethers.getContractFactory(
        "ExilonNftLootboxMaster"
    );
    arguments = [
        exilonAddress,
        exilonAddress,
        usdAddress,
        dexRouterAddress,
        FeeReceiverInst.address,
        AccessInst.address,
        ExilonNftLootboxMainInst.address,
        FundsHolderFactoryInst.address,
    ];
    console.log("Deploying ExilonNftLootboxMaster...");
    const ExilonNftLootboxMasterInst = await ExilonNftLootboxMasterFactory.deploy(...arguments);
    await ExilonNftLootboxMasterInst.deployed();
    console.log("ExilonNftLootboxMaster deployed at", ExilonNftLootboxMasterInst.address);
    try {
        await hre.run("verify:verify", {
            address: ExilonNftLootboxMasterInst.address,
            constructorArguments: arguments,
        });
    } catch (error) {
        console.log("Error =", error);
    }

    /* await hre.run("verify:verify", {
        address: await ExilonNftLootboxInst.masterContract(),
        libraries: {
            ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
        }
    }); */

    const ERC721MainFactory = await hre.ethers.getContractFactory("ERC721Main");
    arguments = [usdAddress, dexRouterAddress, FeeReceiverInst.address, AccessInst.address];
    console.log("Deploying ERC721Main...");
    const ERC721MainInst = await ERC721MainFactory.deploy(...arguments);
    await ERC721MainInst.deployed();
    console.log("ERC721Main deployed at", ERC721MainInst.address);
    try {
        await hre.run("verify:verify", {
            address: ERC721MainInst.address,
            constructorArguments: arguments,
        });
    } catch (error) {
        console.log("Error =", error);
    }

    const ERC1155MainFactory = await hre.ethers.getContractFactory("ERC1155Main");
    console.log("Deploying ERC1155Main...");
    const ERC1155MainInst = await ERC1155MainFactory.deploy(...arguments);
    await ERC1155MainInst.deployed();
    console.log("ERC1155Main deployed at", ERC1155MainInst.address);
    try {
        await hre.run("verify:verify", {
            address: ERC1155MainInst.address,
            constructorArguments: arguments,
        });
    } catch (error) {
        console.log("Error =", error);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
