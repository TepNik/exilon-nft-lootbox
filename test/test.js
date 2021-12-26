const { expect } = require("chai");

const BN = ethers.BigNumber;

const Eighteen = BN.from(18);
const OneEth = BN.from(10).pow(Eighteen);
const OneExilon = BN.from(10).pow(Eighteen);
const OneUsd = BN.from(10).pow(Eighteen);
const OneToken = BN.from(10).pow(Eighteen);

const Deadline = BN.from("1000000000000000");

describe("Exilon Nft Lootbox test", function () {
    let WETHInst;
    let PancakeFactoryInst;
    let PancakeRouterInst;

    let ExilonNftLootboxLibraryInst;
    let ExilonNftLootboxInst;

    let ExilonInst;
    let UsdInst;
    let Erc20Inst;

    let Erc721Inst;
    let Erc1155Inst;

    let deployer;
    let user;
    let feeReceiver;

    beforeEach(async () => {
        [deployer, feeToSetter, feeReceiver, user] = await ethers.getSigners();

        const WETHFactory = await hre.ethers.getContractFactory("WETH");
        WETHInst = await WETHFactory.deploy();
        const PancakeFactoryFactory = await hre.ethers.getContractFactory("PancakeFactory");
        PancakeFactoryInst = await PancakeFactoryFactory.deploy(feeToSetter.address);
        const PancakeRouterFactory = await hre.ethers.getContractFactory("PancakeRouter");
        PancakeRouterInst = await PancakeRouterFactory.deploy(
            PancakeFactoryInst.address,
            WETHInst.address
        );

        const ExilonNftLootboxLibraryFactory = await hre.ethers.getContractFactory(
            "ExilonNftLootboxLibrary"
        );
        ExilonNftLootboxLibraryInst = await ExilonNftLootboxLibraryFactory.deploy();

        const ERC20TestFactorty = await hre.ethers.getContractFactory("ERC20Test");
        ExilonInst = await ERC20TestFactorty.deploy();
        UsdInst = await ERC20TestFactorty.deploy();
        Erc20Inst = await ERC20TestFactorty.deploy();

        const ERC721TestFactorty = await hre.ethers.getContractFactory("ERC721Test");
        Erc721Inst = await ERC721TestFactorty.deploy();

        const ERC1155TestFactorty = await hre.ethers.getContractFactory("ERC1155Test");
        Erc1155Inst = await ERC1155TestFactorty.deploy();

        const ExilonNftLootboxFactory = await hre.ethers.getContractFactory("ExilonNftLootbox", {
            libraries: {
                ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
            },
        });
        ExilonNftLootboxInst = await ExilonNftLootboxFactory.deploy(
            ExilonInst.address,
            UsdInst.address,
            PancakeRouterInst.address,
            feeReceiver.address
        );

        let amountOfExilonToPair = OneExilon.mul(1000);
        let amountOfEthToExilonPair = OneEth.mul(2);
        await ExilonInst.mint(amountOfExilonToPair);
        await ExilonInst.approve(PancakeRouterInst.address, amountOfExilonToPair);
        await PancakeRouterInst.addLiquidityETH(
            ExilonInst.address,
            amountOfExilonToPair,
            0,
            0,
            deployer.address,
            Deadline,
            { value: amountOfEthToExilonPair }
        );

        let amountOfUsdToPair = OneUsd.mul(2000);
        let amountOfEthToUsdPair = OneEth.mul(3);
        await UsdInst.mint(amountOfUsdToPair);
        await UsdInst.approve(PancakeRouterInst.address, amountOfUsdToPair);
        await PancakeRouterInst.addLiquidityETH(
            UsdInst.address,
            amountOfUsdToPair,
            0,
            0,
            deployer.address,
            Deadline,
            { value: amountOfEthToUsdPair }
        );
    });

    it("Pack and unpack test", async () => {
        let amountOfErc20ToBox = OneToken.mul(10);
        await Erc20Inst.mint(amountOfErc20ToBox);
        await Erc20Inst.approve(ExilonNftLootboxInst.address, amountOfErc20ToBox);

        let idOfErc721 = BN.from(1);
        await Erc721Inst.mint(idOfErc721);
        await Erc721Inst.setApprovalForAll(ExilonNftLootboxInst.address, true);

        let idOfErc1155 = BN.from(2);
        let amountOfErc1155 = BN.from(10);
        await Erc1155Inst.mint(idOfErc1155, amountOfErc1155);
        await Erc1155Inst.setApprovalForAll(ExilonNftLootboxInst.address, true);

        let prizeInfo = [];
        prizeInfo.push({
            placeAmounts: 1,
            prizesInfo: [
                {
                    tokenAddress: Erc20Inst.address,
                    tokenType: 0,
                    id: 0,
                    amount: amountOfErc20ToBox,
                },
            ],
        });
        prizeInfo.push({
            placeAmounts: 1,
            prizesInfo: [
                {
                    tokenAddress: Erc721Inst.address,
                    tokenType: 1,
                    id: idOfErc721,
                    amount: 0,
                },
            ],
        });
        prizeInfo.push({
            placeAmounts: 1,
            prizesInfo: [
                {
                    tokenAddress: Erc1155Inst.address,
                    tokenType: 2,
                    id: idOfErc1155,
                    amount: amountOfErc1155,
                },
            ],
        });
        prizeInfo.push({
            placeAmounts: 2,
            prizesInfo: [],
        });

        expect(await Erc20Inst.balanceOf(deployer.address)).to.be.equals(amountOfErc20ToBox);
        expect(await Erc721Inst.ownerOf(idOfErc721)).to.be.equals(deployer.address);
        expect(await Erc1155Inst.balanceOf(deployer.address, idOfErc1155)).to.be.equals(
            amountOfErc1155
        );

        await ExilonNftLootboxInst.makeLootBox(prizeInfo, OneUsd, true, "", {
            value: await ExilonNftLootboxInst.getBnbPriceToCreate(),
        });

        expect(
            await ExilonNftLootboxInst.getUsersIdsLength(ExilonNftLootboxInst.address)
        ).to.be.equals(1);
        let ids = await ExilonNftLootboxInst.getUsersIds(ExilonNftLootboxInst.address, 0, 1);
        expect(ids.length).to.be.equals(1);
        expect(ids[0]).to.be.equals(0);

        let fundsHolder = await ExilonNftLootboxInst.idsToFundsHolders(0);

        expect(await Erc20Inst.balanceOf(fundsHolder)).to.be.equals(amountOfErc20ToBox);
        expect(await Erc721Inst.ownerOf(idOfErc721)).to.be.equals(fundsHolder);
        expect(await Erc1155Inst.balanceOf(fundsHolder, idOfErc1155)).to.be.equals(amountOfErc1155);

        await ExilonNftLootboxInst.connect(user).buyId(0, 5, {
            value: await ExilonNftLootboxInst.getBnbPriceToOpen(0, 6),
        });

        expect(await Erc20Inst.balanceOf(user.address)).to.be.equals(amountOfErc20ToBox);
        expect(await Erc721Inst.ownerOf(idOfErc721)).to.be.equals(user.address);
        expect(await Erc1155Inst.balanceOf(user.address, idOfErc1155)).to.be.equals(
            amountOfErc1155
        );
    });
});
