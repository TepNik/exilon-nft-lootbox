
const deployAndVerify = async (contractName, arguments) => {
	const Contract = await hre.ethers.getContractFactory(contractName);

    console.log("Deploying Contact...");
    const contract = await Contract.deploy(...arguments);
    console.log(`${contractName} deployed to: ${contract.address}`);

    await contract.deployed();
    console.log("Done");

    const networkName = hre.network.name;
    console.log("Network:", networkName);
    if (networkName != "hardhat") {
        console.log("Verifying contract...");
        await hre.run("verify:verify", {
            address: contract.address,
            constructorArguments: arguments,
        });
        console.log("Contract is Verified");
    }

}

module.exports = {
	deployAndVerify
}