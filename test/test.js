const { expect } = require("chai");
const { constants, expectEvent, expectRevert, snapshot } = require("@openzeppelin/test-helpers");

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
    let ExilonNftLootboxMasterInst;
    let ExilonNftLootboxMainInst;

    let FeeReceiverInst;
    let feeRecipients;
    let feeRecipientAmounts;

    let ExilonInst;
    let UsdInst;
    let Erc20Inst;

    let Erc721Inst;
    let Erc1155Inst;

    let deployer;
    let user;
    let feeReceiver;

    beforeEach(async () => {
        [deployer, feeToSetter, feeReceiver, user, feeReceiver1, feeReceiver2] =
            await ethers.getSigners();
        hre.tracer.nameTags[deployer.address] = "deployer";
        hre.tracer.nameTags[user.address] = "user";

        const WETHFactory = await hre.ethers.getContractFactory("WETH");
        WETHInst = await WETHFactory.deploy();
        const PancakeFactoryFactory = await hre.ethers.getContractFactory("PancakeFactory");
        PancakeFactoryInst = await PancakeFactoryFactory.deploy(feeToSetter.address);
        const PancakeRouterFactory = await hre.ethers.getContractFactory("PancakeRouter");
        PancakeRouterInst = await PancakeRouterFactory.deploy(
            PancakeFactoryInst.address,
            WETHInst.address
        );

        const AccessFactory = await hre.ethers.getContractFactory("Access");
        AccessInst = await AccessFactory.deploy();
        hre.tracer.nameTags[AccessInst.address] = "AccessInst";

        const FeeReceiverFactory = await hre.ethers.getContractFactory("FeeReceiver");
        feeRecipients = [feeReceiver1.address, feeReceiver2.address];
        feeRecipientAmounts = [1, 2];
        FeeReceiverInst = await FeeReceiverFactory.deploy(
            feeRecipients,
            feeRecipientAmounts,
            AccessInst.address
        );
        hre.tracer.nameTags[FeeReceiverInst.address] = "FeeReceiverInst";
        await FeeReceiverInst.setMinimalAmountToDistribute(0);

        const ExilonNftLootboxLibraryFactory = await hre.ethers.getContractFactory(
            "ExilonNftLootboxLibrary"
        );
        ExilonNftLootboxLibraryInst = await ExilonNftLootboxLibraryFactory.deploy();
        hre.tracer.nameTags[ExilonNftLootboxLibraryInst.address] = "ExilonNftLootboxLibraryInst";

        const ERC20TestFactorty = await hre.ethers.getContractFactory("ERC20Test");
        ExilonInst = await ERC20TestFactorty.deploy();
        hre.tracer.nameTags[ExilonInst.address] = "ExilonInst";
        UsdInst = await ERC20TestFactorty.deploy();
        hre.tracer.nameTags[UsdInst.address] = "UsdInst";
        Erc20Inst = await ERC20TestFactorty.deploy();
        hre.tracer.nameTags[Erc20Inst.address] = "Erc20Inst";

        const ERC721TestFactorty = await hre.ethers.getContractFactory("ERC721Test");
        Erc721Inst = await ERC721TestFactorty.deploy();
        hre.tracer.nameTags[Erc721Inst.address] = "Erc721Inst";

        const ERC1155TestFactorty = await hre.ethers.getContractFactory("ERC1155Test");
        Erc1155Inst = await ERC1155TestFactorty.deploy();
        hre.tracer.nameTags[Erc1155Inst.address] = "Erc1155Inst";

        const NftMarketplaceFactory = await hre.ethers.getContractFactory("NftMarketplace", {
            libraries: {
                ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
            },
        });
        NftMarketplaceInst = await NftMarketplaceFactory.deploy(
            UsdInst.address,
            PancakeRouterInst.address,
            FeeReceiverInst.address,
            AccessInst.address
        );
        hre.tracer.nameTags[NftMarketplaceInst.address] = "NftMarketplaceInst";

        const ExilonNftLootboxMainFactory = await hre.ethers.getContractFactory(
            "ExilonNftLootboxMain",
            {
                libraries: {
                    ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
                },
            }
        );
        ExilonNftLootboxMainInst = await ExilonNftLootboxMainFactory.deploy(
            NftMarketplaceInst.address,
            UsdInst.address,
            PancakeRouterInst.address,
            FeeReceiverInst.address,
            AccessInst.address
        );
        hre.tracer.nameTags[ExilonNftLootboxMainInst.address] = "ExilonNftLootboxMainInst";

        const FundsHolderFactoryFactory = await hre.ethers.getContractFactory(
            "FundsHolderFactory",
            {
                libraries: {
                    ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
                },
            }
        );
        FundsHolderFactoryInst = await FundsHolderFactoryFactory.deploy();
        hre.tracer.nameTags[FundsHolderFactoryInst.address] = "FundsHolderFactoryInst";

        const PriceHolderFactory = await hre.ethers.getContractFactory("PriceHolder", {
            libraries: {
                ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
            },
        });
        PriceHolderInst = await PriceHolderFactory.deploy(
            ExilonInst.address,
            UsdInst.address,
            PancakeRouterInst.address,
            AccessInst.address,
            ExilonNftLootboxMainInst.address
        );
        hre.tracer.nameTags[PriceHolderInst.address] = "PriceHolderInst";

        const ExilonNftLootboxMasterFactory = await hre.ethers.getContractFactory(
            "ExilonNftLootboxMaster",
            {
                libraries: {
                    ExilonNftLootboxLibrary: ExilonNftLootboxLibraryInst.address,
                },
            }
        );
        ExilonNftLootboxMasterInst = await ExilonNftLootboxMasterFactory.deploy(
            ExilonInst.address,
            UsdInst.address,
            PancakeRouterInst.address,
            FeeReceiverInst.address,
            AccessInst.address,
            ExilonNftLootboxMainInst.address,
            FundsHolderFactoryInst.address,
            PriceHolderInst.address
        );
        hre.tracer.nameTags[ExilonNftLootboxMasterInst.address] = "ExilonNftLootboxMasterInst";

        await addLiquidityETH(ExilonInst);
        await addLiquidityETH(UsdInst);
    });

    it("Pack and unpack test", async () => {
        let amountOfErc20ToBox = OneToken.mul(40);
        await Erc20Inst.mint(amountOfErc20ToBox);
        await Erc20Inst.approve(ExilonNftLootboxMasterInst.address, amountOfErc20ToBox);

        let idOfErc721 = BN.from(1);
        await Erc721Inst.mint(idOfErc721);
        await Erc721Inst.setApprovalForAll(ExilonNftLootboxMasterInst.address, true);

        let idOfErc1155 = BN.from(2);
        let amountOfErc1155 = BN.from(10);
        await Erc1155Inst.mint(idOfErc1155, amountOfErc1155);
        await Erc1155Inst.setApprovalForAll(ExilonNftLootboxMasterInst.address, true);

        let prizeInfo = [];
        prizeInfo.push({
            placeAmounts: 2,
            prizesInfo: [
                {
                    tokenAddress: Erc20Inst.address,
                    tokenType: 0,
                    id: 0,
                    amount: amountOfErc20ToBox.div(8),
                },
                {
                    tokenAddress: Erc20Inst.address,
                    tokenType: 0,
                    id: 0,
                    amount: amountOfErc20ToBox.div(8),
                },
            ],
        });
        prizeInfo.push({
            placeAmounts: 2,
            prizesInfo: [
                {
                    tokenAddress: Erc20Inst.address,
                    tokenType: 0,
                    id: 0,
                    amount: amountOfErc20ToBox.div(4),
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

        await ExilonNftLootboxMasterInst.makeLootBox(prizeInfo, OneUsd, true, "", {
            value: await PriceHolderInst.getBnbPriceToCreate(),
        });

        expect(
            await ExilonNftLootboxMainInst.getUsersIdsLength(ExilonNftLootboxMasterInst.address)
        ).to.be.equals(1);
        let ids = await ExilonNftLootboxMainInst.getUsersIds(
            ExilonNftLootboxMasterInst.address,
            0,
            1
        );
        expect(ids.length).to.be.equals(1);
        expect(ids[0]).to.be.equals(0);

        let fundsHolder = await ExilonNftLootboxMasterInst.idsToFundsHolders(0);

        expect(await Erc20Inst.balanceOf(fundsHolder)).to.be.equals(amountOfErc20ToBox);
        expect(await Erc721Inst.ownerOf(idOfErc721)).to.be.equals(fundsHolder);
        expect(await Erc1155Inst.balanceOf(fundsHolder, idOfErc1155)).to.be.equals(amountOfErc1155);

        let snapshotBeforeOpening = await snapshot();

        await ExilonNftLootboxMasterInst.connect(user).buyId(0, 8, {
            value: await PriceHolderInst.getBnbPriceToOpen(user.address, 0, 8),
        });

        expect(await Erc20Inst.balanceOf(user.address)).to.be.equals(amountOfErc20ToBox);
        expect(await Erc721Inst.ownerOf(idOfErc721)).to.be.equals(user.address);
        expect(await Erc1155Inst.balanceOf(user.address, idOfErc1155)).to.be.equals(
            amountOfErc1155
        );

        await snapshotBeforeOpening.restore();

        await Erc20Inst.switchTransfers();

        tx = await (
            await ExilonNftLootboxMasterInst.connect(user).buyId(0, 8, {
                value: await PriceHolderInst.getBnbPriceToOpen(user.address, 0, 8),
            })
        ).wait();
        for (let i = 0; i < tx.events.length; ++i) {
            if (tx.events[i].address == fundsHolder) {
                let data = ethers.utils.defaultAbiCoder.decode(
                    ["uint256", "string"],
                    tx.events[i].data
                );
                expect(data[1]).to.be.equals("ERC20Test: Transfers disabled");
            }
        }

        await snapshotBeforeOpening.restore();

        await Erc721Inst.switchTransfers();

        tx = await (
            await ExilonNftLootboxMasterInst.connect(user).buyId(0, 8, {
                value: await PriceHolderInst.getBnbPriceToOpen(user.address, 0, 8),
            })
        ).wait();
        for (let i = 0; i < tx.events.length; ++i) {
            if (tx.events[i].address == fundsHolder) {
                let data = ethers.utils.defaultAbiCoder.decode(
                    ["uint256", "string"],
                    tx.events[i].data
                );
                expect(data[1]).to.be.equals("ERC721Test: Transfers disabled");
            }
        }

        await snapshotBeforeOpening.restore();

        await Erc1155Inst.switchTransfers();

        tx = await (
            await ExilonNftLootboxMasterInst.connect(user).buyId(0, 8, {
                value: await PriceHolderInst.getBnbPriceToOpen(user.address, 0, 8),
            })
        ).wait();
        for (let i = 0; i < tx.events.length; ++i) {
            if (tx.events[i].address == fundsHolder) {
                let data = ethers.utils.defaultAbiCoder.decode(
                    ["uint256", "uint256", "string"],
                    tx.events[i].data
                );
                expect(data[2]).to.be.equals("ERC1155Test: Transfers disabled");
            }
        }

        await snapshotBeforeOpening.restore();

        hre.tracer.nameTags[await ExilonNftLootboxMasterInst.idsToFundsHolders(0)] =
            "FundsHolder(0)";

        let totalAmountPlaces = 0;
        for (winningPlace of prizeInfo) {
            totalAmountPlaces += winningPlace.placeAmounts;
        }
        await UsdInst.mint(OneUsd.mul(totalAmountPlaces));
        await UsdInst.approve(ExilonNftLootboxMainInst.address, OneUsd.mul(totalAmountPlaces));
        await addLiquidityETH(Erc20Inst);
        await ExilonNftLootboxMainInst.setIdMega(0, 1);
        for (let i = 0; i < prizeInfo.length; ++i) {
            await ExilonNftLootboxMasterInst.removeWinningPlace(
                0,
                0,
                prizeInfo[i].placeAmounts,
                deployer.address
            );
        }

        await snapshotBeforeOpening.restore();

        hre.tracer.nameTags[await ExilonNftLootboxMasterInst.idsToFundsHolders(0)] =
            "FundsHolder(0)";

        await UsdInst.connect(user).mint(OneUsd.mul(totalAmountPlaces));
        await UsdInst.connect(user).approve(
            ExilonNftLootboxMainInst.address,
            OneUsd.mul(totalAmountPlaces)
        );
        await UsdInst.mint(OneUsd.mul(totalAmountPlaces));
        await UsdInst.approve(ExilonNftLootboxMainInst.address, OneUsd.mul(totalAmountPlaces));
        await addLiquidityETH(Erc20Inst);
        await ExilonNftLootboxMainInst.setIdMega(0, 1);

        await Erc20Inst.connect(user).mint(amountOfErc20ToBox);
        await Erc20Inst.connect(user).approve(
            ExilonNftLootboxMasterInst.address,
            amountOfErc20ToBox
        );

        idOfErc721 = idOfErc721.add(1);
        prizeInfo[2].prizesInfo[0].id = idOfErc721;
        await Erc721Inst.connect(user).mint(idOfErc721);
        await Erc721Inst.connect(user).setApprovalForAll(ExilonNftLootboxMasterInst.address, true);

        await Erc1155Inst.connect(user).mint(idOfErc1155, amountOfErc1155);
        await Erc1155Inst.connect(user).setApprovalForAll(ExilonNftLootboxMasterInst.address, true);

        await ExilonNftLootboxMasterInst.connect(user).makeLootBox(prizeInfo, OneUsd, true, "", {
            value: await PriceHolderInst.getBnbPriceToCreate(),
        });

        await NftMarketplaceInst.connect(user).sendAddressOnModeration(
            {
                tokenAddress: ExilonNftLootboxMainInst.address,
                tokenType: 2,
                id: 1,
                amount: 0,
            },
            { value: await NftMarketplaceInst.getBnbPriceForModeration() }
        );
        await NftMarketplaceInst.processModeration(ExilonNftLootboxMainInst.address, 1, true);

        await ExilonNftLootboxMainInst.connect(user).requestIdForMerge(1, 0, {
            value: await ExilonNftLootboxMainInst.getBnbPriceToMergeRequest(),
        });
        await ExilonNftLootboxMainInst.connect(deployer).processMergeRequest(1, true);

        await ExilonNftLootboxMasterInst.connect(user).buyId(0, 16, {
            value: await PriceHolderInst.getBnbPriceToOpen(user.address, 0, 16),
        });

        await snapshotBeforeOpening.restore();

        await ExilonNftLootboxMasterInst.connect(user).buyId(0, 8, {
            value: await PriceHolderInst.getBnbPriceToOpen(user.address, 0, 8),
        });

        const fundsHolder1 = await ExilonNftLootboxMasterInst.idsToFundsHolders(1);
        hre.tracer.nameTags[fundsHolder1] = "FundsHolder(1)";

        await Erc20Inst.connect(user).mint(amountOfErc20ToBox);
        await Erc20Inst.connect(user).approve(
            ExilonNftLootboxMasterInst.address,
            amountOfErc20ToBox
        );

        await ExilonNftLootboxMasterInst.connect(user).makeLootBox(
            [prizeInfo[0], prizeInfo[1]],
            OneUsd,
            true,
            "",
            {
                value: await PriceHolderInst.getBnbPriceToCreate(),
            }
        );

        await UsdInst.mint(OneUsd.mul(totalAmountPlaces));
        await UsdInst.approve(ExilonNftLootboxMainInst.address, OneUsd.mul(totalAmountPlaces));
        await addLiquidityETH(Erc20Inst);
        await ExilonNftLootboxMainInst.setIdMega(1, 1);

        await PriceHolderInst.setRandomParams(10000, 100000, 2);

        await ExilonNftLootboxMasterInst.connect(user).buyId(1, 1, {
            value: await PriceHolderInst.getBnbPriceToOpen(user.address, 1, 1),
        });

        let prizesInfoContract = await ExilonNftLootboxMasterInst.getRestPrizesInfo(1, 0, 2);
        for (let i = 0; i < 2; ++i) {
            await ExilonNftLootboxMasterInst.removeWinningPlace(
                1,
                0,
                prizesInfoContract[i].placeAmounts,
                user.address
            );
        }

        console.log("balance after token =", (await Erc20Inst.balanceOf(fundsHolder1)).toString());
        console.log(
            "balance after usd =",
            (await UsdInst.balanceOf(ExilonNftLootboxMainInst.address)).toString()
        );
    });

    async function addLiquidityETH(token) {
        let amountOfTokenToPair = BN.from(10)
            .pow(await token.decimals())
            .mul(1000);
        let amountOfEthToPair = OneEth.mul(2);
        await token.mint(amountOfTokenToPair);
        await token.approve(PancakeRouterInst.address, amountOfTokenToPair);
        await PancakeRouterInst.addLiquidityETH(
            token.address,
            amountOfTokenToPair,
            0,
            0,
            deployer.address,
            Deadline,
            { value: amountOfEthToPair }
        );
    }
});
