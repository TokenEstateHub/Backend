require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");
require("dotenv").config({ path: ".env" });

console.log(process.env.ALCHEMY_TESTNET_RPC_URL);

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.27",
  networks: {
    sepolia: {
      url: process.env.ALCHEMY_TESTNET_RPC_URL, // Sepolia RPC from .env
      accounts: [process.env.PRIVATE_KEY], // Deployer private key from .env
    },
    lisksepolia: {
      url: "https://rpc.sepolia-api.lisk.com", // Updated RPC URL
      chainId: 4202,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: {
      sepolia: "4RG4F3IGAC7ZXNUN9JQFEXAXBEYFJGRNXJ", // Your Sepolia Etherscan API key
      lisksepolia: "no-api-key-needed", // Lisk Sepolia uses its own explorer, placeholder here
    },
    customChains: [
      {
        network: "sepolia",
        chainId: 11155111,
        urls: {
          apiURL: "https://api-sepolia.etherscan.io/api",
          browserURL: "https://sepolia.etherscan.io",
        },
      },
      {
        network: "lisksepolia", // Added Lisk Sepolia custom chain
        chainId: 4202,
        urls: {
          apiURL: "https://sepolia-blockscout.lisk.com/api", // Lisk Sepolia Blockscout API
          browserURL: "https://sepolia-blockscout.lisk.com", // Lisk Sepolia Blockscout explorer
        },
      },
    ],
  },
  sourcify: {
    enabled: true,
    apiUrl: "https://sourcify.dev/server",
    browserUrl: "https://repo.sourcify.dev",
  },
};
