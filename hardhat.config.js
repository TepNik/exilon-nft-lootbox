require("@nomiclabs/hardhat-waffle");

// Automatic verification on etherscan, bscscan and others
// command: npx hardhat verify --network mainnet DEPLOYED_CONTRACT_ADDRESS
require("@nomiclabs/hardhat-etherscan");

// command: npx hardhat coverage
require("solidity-coverage");

// Writes bytecode sizes of smart contracts
require("hardhat-contract-sizer");

// Writes information of gas usage in tests
require("hardhat-gas-reporter");

// Exports smart contract ABIs on compilation
require("hardhat-abi-exporter");

// Writes SPDX License Identifier into sol files
// Type of license it takes from package.json
require("hardhat-spdx-license-identifier");

// command: npx hardhat check
require("@nomiclabs/hardhat-solhint");

// Prints events when running tests
// command: npx hardhat test --logs
require("hardhat-tracer");

require("@nomiclabs/hardhat-web3");

let config = require("./config.json");

module.exports = {
    networks: {
        hardhat: {},
        ethereumMainnet: {
            url: "https://rinkeby.infura.io/v3/" + config.infuraIdProject,
            accounts: config.mainnetAccounts,
        },
        ropsten: {
            url: "https://ropsten.infura.io/v3/" + config.infuraIdProject,
            accounts: config.testnetAccounts,
        },
        kovan: {
            url: "https://kovan.infura.io/v3/" + config.infuraIdProject,
            accounts: config.testnetAccounts,
        },
        rinkeby: {
            url: "https://rinkeby.infura.io/v3/" + config.infuraIdProject,
            accounts: config.testnetAccounts,
        },
        goerli: {
            url: "https://goerli.infura.io/v3/" + config.infuraIdProject,
            accounts: config.testnetAccounts,
        },
        bscMainnet: {
            url: "https://bsc-dataseed3.binance.org",
            accounts: config.mainnetAccounts,
            timeout: 100000000,
        },
        bscTestnet: {
            url: "https://data-seed-prebsc-1-s1.binance.org:8545",
            accounts: config.testnetAccounts,
            timeout: 100000000,
        },
        polygonMainnet: {
            url: "https://rpc-mainnet.maticvigil.com",
            accounts: config.mainnetAccounts,
        },
        polygonTestnet: {
            url: "https://matic-mumbai.chainstacklabs.com",
            accounts: config.testnetAccounts,
        },
    },
    etherscan: {
        apiKey: config.apiKey,
    },
    solidity: {
        compilers: [
            {
                version: "0.8.11",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    mocha: {
        timeout: 100000,
    },
    contractSizer: {
        alphaSort: true,
        runOnCompile: false,
        disambiguatePaths: false,
    },
    gasReporter: {
        currency: "USD",
        coinmarketcap: config.coinmarketcapApi,
        token: "BNB",
        gasPriceApi: "https://api.bscscan.com/api?module=proxy&action=eth_gasPrice",
    },
    abiExporter: {
        path: "./data/abi",
        clear: true,
        flat: true,
        spacing: 2,
    },
    spdxLicenseIdentifier: {
        overwrite: true,
        runOnCompile: true,
    },
};
