const hre = require("hardhat");

const config = require("../config.json");

async function main() {
    if (hre.network.name != "bscTestnet" && hre.network.name != "bscMainnet") {
        console.log("Wrong network");
        return;
    }

    const [deployer] = await ethers.getSigners();
    console.log("Deployer:", deployer.address, "\n");

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
    let deployTx = await AccessInst.deployTransaction.wait();
    console.log("Used gas:", deployTx.gasUsed.toString(), "\n");

    const FeeReceiverFactory = await hre.ethers.getContractFactory("FeeReceiver");
    let arguments = [config.feeReceivers, config.feeReceiverAmounts, AccessInst.address];
    console.log("Deploying FeeReceiver...");
    const FeeReceiverInst = await FeeReceiverFactory.deploy(...arguments);
    await FeeReceiverInst.deployed();
    console.log("FeeReceiver deployed at", FeeReceiverInst.address);
    deployTx = await FeeReceiverInst.deployTransaction.wait();
    console.log("Used gas:", deployTx.gasUsed.toString(), "\n");

    const ExilonNftLootboxLibraryFactory = await hre.ethers.getContractFactory(
        "ExilonNftLootboxLibrary"
    );
    console.log("Deploying ExilonNftLootboxLibrary...");
    const ExilonNftLootboxLibraryInst = await ExilonNftLootboxLibraryFactory.deploy();
    await ExilonNftLootboxLibraryInst.deployed();
    console.log("ExilonNftLootboxLibrary deployed at", ExilonNftLootboxLibraryInst.address);
    deployTx = await ExilonNftLootboxLibraryInst.deployTransaction.wait();
    console.log("Used gas:", deployTx.gasUsed.toString(), "\n");

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
    deployTx = await NftMarketplaceInst.deployTransaction.wait();
    console.log("Used gas:", deployTx.gasUsed.toString(), "\n");

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
    deployTx = await ExilonNftLootboxMainInst.deployTransaction.wait();
    console.log("Used gas:", deployTx.gasUsed.toString(), "\n");

    const FundsHolderFactoryFactory = await hre.ethers.getContractFactory("FundsHolderFactory", {
        libraries: {
            ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
        },
    });
    console.log("Deploying FundsHolderFactory...");
    const FundsHolderFactoryInst = await FundsHolderFactoryFactory.deploy();
    await FundsHolderFactoryInst.deployed();
    console.log("FundsHolderFactory deployed at", FundsHolderFactoryInst.address);
    deployTx = await FundsHolderFactoryInst.deployTransaction.wait();
    console.log("Used gas:", deployTx.gasUsed.toString(), "\n");

    const PriceHolderFactory = await hre.ethers.getContractFactory("PriceHolder", {
        libraries: {
            ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
        },
    });
    console.log("Deploying PriceHolder...");
    const PriceHolderInst = await PriceHolderFactory.deploy(
        //exilonAddress,
        ethers.constants.AddressZero,
        usdAddress,
        dexRouterAddress,
        AccessInst.address,
        ExilonNftLootboxMainInst.address
    );
    console.log("PriceHolder deployed at", PriceHolderInst.address);
    deployTx = await PriceHolderInst.deployTransaction.wait();
    console.log("Used gas:", deployTx.gasUsed.toString(), "\n");

    const ExilonNftLootboxMasterFactory = await hre.ethers.getContractFactory(
        "ExilonNftLootboxMaster",
        {
            libraries: {
                ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
            },
        }
    );
    arguments = [
        exilonAddress,
        usdAddress,
        dexRouterAddress,
        FeeReceiverInst.address,
        AccessInst.address,
        ExilonNftLootboxMainInst.address,
        FundsHolderFactoryInst.address,
        PriceHolderInst.address,
    ];
    console.log("Deploying ExilonNftLootboxMaster...");
    const ExilonNftLootboxMasterInst = await ExilonNftLootboxMasterFactory.deploy(...arguments);
    await ExilonNftLootboxMasterInst.deployed();
    console.log("ExilonNftLootboxMaster deployed at", ExilonNftLootboxMasterInst.address);
    deployTx = await ExilonNftLootboxMasterInst.deployTransaction.wait();
    console.log("Used gas:", deployTx.gasUsed.toString(), "\n");

    const ERC721MainFactory = await hre.ethers.getContractFactory("ERC721Main");
    arguments = [usdAddress, dexRouterAddress, FeeReceiverInst.address, AccessInst.address];
    console.log("Deploying ERC721Main...");
    const ERC721MainInst = await ERC721MainFactory.deploy(...arguments);
    await ERC721MainInst.deployed();
    console.log("ERC721Main deployed at", ERC721MainInst.address);
    deployTx = await ERC721MainInst.deployTransaction.wait();
    console.log("Used gas:", deployTx.gasUsed.toString(), "\n");

    const ERC1155MainFactory = await hre.ethers.getContractFactory("ERC1155Main");
    console.log("Deploying ERC1155Main...");
    const ERC1155MainInst = await ERC1155MainFactory.deploy(...arguments);
    await ERC1155MainInst.deployed();
    console.log("ERC1155Main deployed at", ERC1155MainInst.address);
    deployTx = await ERC1155MainInst.deployTransaction.wait();
    console.log("Used gas:", deployTx.gasUsed.toString(), "\n");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
