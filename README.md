# TokenEstate

TokenEstate is a decentralized application (dApp) for tokenizing real estate properties, enabling their purchase and rental on the Ethereum blockchain. This project uses Solidity smart contracts deployed on the Sepolia testnet, leveraging ERC20 tokens (UtilityToken) for payments and an escrow system for secure transactions.

## Project Overview

**Objective**: Tokenize real estate assets, facilitate property purchases, and manage rentals with a secure escrow mechanism.

**Network**: Ethereum Sepolia Testnet

**Tools**: Hardhat, Solidity, Ethers.js, Alchemy

### Contracts:

- **UtilityToken.sol**: ERC20 token (RET) with decimals = 0 for payments and tokenization.
- **RealEstateManager.sol**: Manages property registration, verification, and tokenization.
- **MarketPlace.sol**: Handles property listings and direct purchases.
- **RentalContract.sol**: Manages rental agreements and income distribution.
- **Escrow.sol**: Secures purchases and rentals with escrow functionality.

---

## Prerequisites

Ensure you have the following installed and set up:

- **Node.js**: v14+ (Install from [nodejs.org](https://nodejs.org/))
- **Hardhat**: Ethereum development environment
- **Alchemy Account**: For Sepolia testnet access (Get API key from [Alchemy](https://www.alchemy.com/))
- **MetaMask**: For wallet management and Sepolia ETH (Fund via faucet)
- **Sepolia ETH**: Obtain from a faucet (e.g., [Alchemy Sepolia Faucet](https://www.alchemy.com/faucets/ethereum-sepolia))

---

## Setup

### Clone the Repository:

```bash
git clone <your-repo-url>
cd TokenEstate
```

### Install Dependencies:

```bash
npm install
npm install --save-dev hardhat @nomiclabs/hardhat-ethers ethers @openzeppelin/contracts
```

### Configure Hardhat:

Edit `hardhat.config.js`:

```javascript
require("@nomiclabs/hardhat-ethers");

module.exports = {
  solidity: "0.8.0",
  networks: {
    sepolia: {
      url: "https://eth-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_API_KEY",
      accounts: ["YOUR_PRIVATE_KEY_HERE"], // Replace with your private key
    },
  },
  paths: {
    sources: "./contracts",
    scripts: "./scripts",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};
```

> ⚠️ **Security Warning:** Never commit your private key to a public repository.

### Add Contracts:

Place the following files in the `contracts` folder:

- `UtilityToken.sol`
- `RealEstateManager.sol`
- `MarketPlace.sol`
- `RentalContract.sol` (updated version with escrowAddress)
- `Escrow.sol`

Ensure they match the versions provided in this project.

---

## Deployment

### Deploying to Sepolia and Lisk Testnet

#### Compile Contracts:

```bash
npx hardhat compile
```

#### Deploy All Contracts:

Run the deployment script:

```bash
npx hardhat run scripts/deploy.js --network sepolia
```

#### Deployed Contracts to Sepolia testnet:

```
Deploying contracts with the account: 0x5805f7d88a125bBb18C9628dA8b57f52d4Bd5003
Deployer ETH balance: ___
UtilityToken deployed to: 0x7923E0aF55FFA2e35B1aE4f6ce611D9CcE00e4Ca
RealEstateManager deployed to: 0x577De3f61e22a9B9CEdCD40bcca4b0EdE566E384
Marketplace deployed to: 0x78426F43f817c3F49DCEf4e47bE107390DE51C13
RentalContract deployed to: 0xF1BaEAbAdcAdACDab5DB9C47997162D9CF9e6eCc
Escrow deployed to: 0x4f3004140018F344cb2a42F698752188528A569C
```

#### Deployed Contracts to Lisk Sepolia testnet:

```
Deploying contracts with the account: 0x5805f7d88a125bBb18C9628dA8b57f52d4Bd5003
Deployer ETH balance: ___
UtilityToken deployed to:0xd1D6Bee21BFf794B788D1D0656ED7AD93a3C452b
RealEstateManager deployed to: 0x3857d74574299A5E8Ff3A13D2b956adb4d969Eb9
Marketplace deployed to: 0x79341CC7546e28b46A58514b4cdB5D6560473C7c
RentalContract deployed to: 0xEA6999B59C2E45051a1bB95842A207714aCC08F0
Escrow deployed to: 0x2a1C1677DAB875425D0a3a0DeeDd1A6F2B751860

```
#### Deployed Contracts to  Etherscan testnet:

-
 **UtilityToken**: (Check from [etherscan.io](https://sepolia.etherscan.io/address/0x7923E0aF55FFA2e35B1aE4f6ce611D9CcE00e4Ca#code)) 

 **RealEstateManager**: (Check from [etherscan.io](https://sepolia.etherscan.io/address/0x577De3f61e22a9B9CEdCD40bcca4b0EdE566E384#code)) 

 **MarketPlace**: (Check from [etherscan.io](https://sepolia.etherscan.io/address/0x78426F43f817c3F49DCEf4e47bE107390DE51C13#code))

 **RentalContract**: (Check from [etherscan.io](https://sepolia.etherscan.io/address/0xF1BaEAbAdcAdACDab5DB9C47997162D9CF9e6eCc#code))

 **Escrow**: (Check from [etherscan.io](https://sepolia.etherscan.io/address/0xF1BaEAbAdcAdACDab5DB9C47997162D9CF9e6eCc#code))









  







---

## Usage

### Adding a Property

**Admin:** Deployer account (e.g., `0x5805f7...5003`).

```javascript
await RealEstateManager(0x[NewRealEstateManagerAddress]).addProperty("Skyline Condo", "789 Sky Ln", 1500, "0xdD870fA1b7C4700F2BD7f44238821C26f7392148");
await RealEstateManager(0x[NewRealEstateManagerAddress]).verifyProperty(1);
await RealEstateManager(0x[NewRealEstateManagerAddress]).tokenizeProperty(1, 100);
```

### Listing for Rent

**Landlord:** `0xdD870fA1b7C4700F2BD7f44238821C26f7392148`

```javascript
await RentalContract(0x[NewRentalAddress]).listForRent(1, 20, 30); // 20 RET, 30 days
```

### Renting a Property

**Tenant:** `0x617F2E2fD72FD9D5503197092aC168c91465E7f2`

```javascript
await UtilityToken(0x[NewUtilityTokenAddress]).approve("0x[NewEscrowAddress]", 20);
await Escrow(0x[NewEscrowAddress]).createRentalEscrow(1);
await Escrow(0x[NewEscrowAddress]).completeEscrow(1);
```

### Distributing Rental Income

After 30 Days:

```javascript
await RentalContract(0x[NewRentalAddress]).distributeRentalIncome(1);
```

---

## Project Structure

```
TokenEstate/
├── contracts/
│   ├── UtilityToken.sol
│   ├── RealEstateManager.sol
│   ├── MarketPlace.sol
│   ├── RentalContract.sol
│   ├── Escrow.sol
├── scripts/
│   ├── deploy.js
│   ├── deploy-rental-only.js
├── hardhat.config.js
├── package.json
└── README.md
```

---

## Troubleshooting

- **Multiple Artifacts Error**: If you see HH701, use fully qualified names (e.g., `contracts/RentalContract.sol:RentalContract`) in the script.
- **Insufficient Funds**: Ensure your deployer account has enough Sepolia ETH (e.g., 0.1 ETH) via a faucet.
- **Private Key Security**: Securely store your key; never commit `hardhat.config.js` with it to a public repo.

---

## Contributing

Feel free to fork this repository, submit pull requests, or open issues for enhancements or bug fixes.

---

## License

This project is licensed under the **GPL-3.0 License** - see the SPDX-License-Identifier in each contract file.

---

## Notes

- **Deployer Address**: Replace `0x5805f7...5003` with your actual deployer address.
- **Alchemy URL**: Replace `YOUR_ALCHEMY_API_KEY` with your real API key.
- **Contract Addresses**: Replace placeholders (e.g., `0x[NewRentalAddress]`) with actual addresses from your deployment output.

This README should guide you or others through setting up and using your TokenEstate project on Sepolia. Let me know if you’d like to tweak it further!
