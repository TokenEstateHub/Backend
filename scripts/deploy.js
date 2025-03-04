const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Deployer ETH balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)));

  const UtilityToken = await hre.ethers.getContractFactory("contracts/UtilityToken.sol:UtilityToken");
  const utilityToken = await UtilityToken.deploy();
  await utilityToken.waitForDeployment();
  const utilityTokenAddress = await utilityToken.getAddress();
  console.log("UtilityToken deployed to:", utilityTokenAddress);

  const RealEstateManager = await hre.ethers.getContractFactory("contracts/RealEstateManager.sol:RealEstateManager");
  const realEstateManager = await RealEstateManager.deploy(utilityTokenAddress);
  await realEstateManager.waitForDeployment();
  const realEstateManagerAddress = await realEstateManager.getAddress();
  console.log("RealEstateManager deployed to:", realEstateManagerAddress);

  const Marketplace = await hre.ethers.getContractFactory("contracts/MarketPlace.sol:Marketplace");
  const marketplace = await Marketplace.deploy(realEstateManagerAddress, utilityTokenAddress);
  await marketplace.waitForDeployment();
  const marketplaceAddress = await marketplace.getAddress();
  console.log("Marketplace deployed to:", marketplaceAddress);

  const RentalContract = await hre.ethers.getContractFactory("contracts/RentalContract.sol:RentalContract");
  const rentalContract = await RentalContract.deploy(utilityTokenAddress, realEstateManagerAddress);
  await rentalContract.waitForDeployment();
  const rentalContractAddress = await rentalContract.getAddress();
  console.log("RentalContract deployed to:", rentalContractAddress);

  const Escrow = await hre.ethers.getContractFactory("contracts/Escrow.sol:Escrow");
  const escrow = await Escrow.deploy(utilityTokenAddress, realEstateManagerAddress);
  await escrow.waitForDeployment();
  const escrowAddress = await escrow.getAddress();
  console.log("Escrow deployed to:", escrowAddress);

  // Configuration steps
  await marketplace.setEscrowAddress(escrowAddress);
  console.log("Marketplace escrowAddress set to:", escrowAddress);
  await rentalContract.setEscrowAddress(escrowAddress);
  console.log("RentalContract escrowAddress set to:", escrowAddress);
  await escrow.setMarketplace(marketplaceAddress);
  await escrow.setRentalContract(rentalContractAddress);
  console.log("Escrow configured with Marketplace and RentalContract");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });