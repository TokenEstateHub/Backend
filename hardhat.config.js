require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");
require('dotenv').config({path:".env"});

console.log(process.env.ALCHEMY_TESTNET_RPC_URL)
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.27",
  networks: {
    sepolia: {
      url: process.env.ALCHEMY_TESTNET_RPC_URL, // Corrected typo
      accounts: [process.env.PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: {
      sepolia: "4RG4F3IGAC7ZXNUN9JQFEXAXBEYFJGRNXJ"
    },
    customChains: [
      {
        network: "sepolia",
        chainId: 11155111,
        urls: {
          apiURL: "https://api-sepolia.etherscan.io/api", // Corrected to use Etherscan API
          browserURL: "https://sepolia.etherscan.io" // Corrected to use Etherscan browser
        }
      }
    ]
  },

  sourcify: {
    enabled: true,
    // Optional: specify a different Sourcify server
    apiUrl: "https://sourcify.dev/server",
    // Optional: specify a different Sourcify repository
    browserUrl: "https://repo.sourcify.dev",
  }
};