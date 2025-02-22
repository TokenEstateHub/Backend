const hre = require("hardhat");

async function main() {
  // Get the deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Check deployer balance
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Deployer ETH balance:", hre.ethers.formatEther(balance));

  // Deploy UtilityToken
  const UtilityToken = await hre.ethers.getContractFactory("contracts/UtilityToken.sol:UtilityToken");
  const utilityToken = await UtilityToken.deploy();
  await utilityToken.waitForDeployment();
  const utilityTokenAddress = await utilityToken.getAddress();
  console.log("UtilityToken deployed to:", utilityTokenAddress);

  // Deploy RealEstateManager
  const RealEstateManager = await hre.ethers.getContractFactory("contracts/RealEstateManager.sol:RealEstateManager");
  const realEstateManager = await RealEstateManager.deploy(utilityTokenAddress);
  await realEstateManager.waitForDeployment();
  const realEstateManagerAddress = await realEstateManager.getAddress();
  console.log("RealEstateManager deployed to:", realEstateManagerAddress);

  // Deploy Marketplace
  const Marketplace = await hre.ethers.getContractFactory("contracts/MarketPlace.sol:Marketplace");
  const marketplace = await Marketplace.deploy(realEstateManagerAddress, utilityTokenAddress);
  await marketplace.waitForDeployment();
  const marketplaceAddress = await marketplace.getAddress();
  console.log("Marketplace deployed to:", marketplaceAddress);

  // Deploy RentalContract with fully qualified name
  const RentalContract = await hre.ethers.getContractFactory("contracts/RentalContract.sol:RentalContract");
  const rentalContract = await RentalContract.deploy(utilityTokenAddress, realEstateManagerAddress);
  await rentalContract.waitForDeployment();
  const rentalContractAddress = await rentalContract.getAddress();
  console.log("RentalContract deployed to:", rentalContractAddress);

  // Deploy Escrow
  const Escrow = await hre.ethers.getContractFactory("contracts/Escrow.sol:Escrow");
  const escrow = await Escrow.deploy(utilityTokenAddress, realEstateManagerAddress);
  await escrow.waitForDeployment();
  const escrowAddress = await escrow.getAddress();
  console.log("Escrow deployed to:", escrowAddress);

  // Configure Marketplace with Escrow address
  console.log("Setting escrowAddress in Marketplace...");
  const setEscrowMarketplaceTx = await marketplace.setEscrowAddress(escrowAddress);
  await setEscrowMarketplaceTx.wait();
  console.log("Marketplace escrowAddress set to:", escrowAddress);

  // Configure RentalContract with Escrow address
  console.log("Setting escrowAddress in RentalContract...");
  const setEscrowRentalTx = await rentalContract.setEscrowAddress(escrowAddress);
  await setEscrowRentalTx.wait();
  console.log("RentalContract escrowAddress set to:", escrowAddress);

  // Configure Escrow with Marketplace and RentalContract addresses
  console.log("Setting marketplace and rentalContract in Escrow...");
  const setMarketplaceTx = await escrow.setMarketplace(marketplaceAddress);
  await setMarketplaceTx.wait();
  const setRentalTx = await escrow.setRentalContract(rentalContractAddress);
  await setRentalTx.wait();
  console.log("Escrow marketplace set to:", marketplaceAddress);
  console.log("Escrow rentalContract set to:", rentalContractAddress);

  // Verify configuration
  console.log("Verifying configuration...");
  const escrowInMarketplace = await marketplace.escrowAddress();
  const escrowInRental = await rentalContract.escrowAddress();
  const marketplaceInEscrow = await escrow.marketplace();
  const rentalInEscrow = await escrow.rentalContract();
  console.log("Marketplace.escrowAddress:", escrowInMarketplace);
  console.log("RentalContract.escrowAddress:", escrowInRental);
  console.log("Escrow.marketplace:", marketplaceInEscrow);
  console.log("Escrow.rentalContract:", rentalInEscrow);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });