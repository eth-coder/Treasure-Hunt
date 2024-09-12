require("@nomicfoundation/hardhat-toolbox");
require("hardhat-deploy");
require("dotenv").config();

const DEPLOYER_KEY = process.env.DEPLOYER_PVT_KEY;
const ALCHEMY_NODE_API_KEY = process.env.ALCHEMY_NODE_API_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

const missingKeys = [];

if (!DEPLOYER_KEY) missingKeys.push("DEPLOYER_PVT_KEY");
if (!ALCHEMY_NODE_API_KEY) missingKeys.push("ALCHEMY_NODE_API_KEY");
if (!ETHERSCAN_API_KEY) missingKeys.push("ETHERSCAN_API_KEY");

if (missingKeys.length > 0) {
  console.warn(
    `Warning: The following environment variable(s) are not set in .env: ${missingKeys.join(
      ", "
    )}`
  );
  console.warn(
    "The project will compile, but some functionality may be limited."
  );
}

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  defaultNetwork: "hardhat",
  namedAccounts: {
    deployer: { default: 0 },
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
    },
    sepolia: {
      accounts: DEPLOYER_KEY ? [DEPLOYER_KEY] : [],
      url: ALCHEMY_NODE_API_KEY
        ? `https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_NODE_API_KEY}`
        : "",
      settings: {
        optimizer: { enabled: true, runs: 9999 },
      },
      live: true,
      gas: "auto",
      saveDeployments: true,
      gasMultiplier: 2,
      chainId: 11155111
    },
  },
  etherscan: {
    apiKey: {
      sepolia: ETHERSCAN_API_KEY || "",
    },
  },
  sourcify: {
    enabled: true,
  },
};
