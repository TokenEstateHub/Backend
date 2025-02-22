// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Marketplace is ReentrancyGuard {
    address public manager;
    address public realEstateManager;
    address public rentalContract;
    IERC20 public utilityToken;
    // *** CHANGE 1: Added escrowAddress state variable ***
    // Purpose: Stores the Escrow contract address to restrict completeEscrowPurchase to Escrow calls
    address public escrowAddress; // Added to recognize Escrow contract

    struct PropertyListing {
        uint propertyId;
        uint price; // Unscaled RET tokens
        address seller;
        bool isAvailable;
        uint expirationTimestamp;
    }

    mapping(uint => PropertyListing) public propertyListings;

    event PropertyListed(uint indexed propertyId, address indexed seller, uint price);
    event PropertySold(uint indexed propertyId, address indexed seller, address indexed buyer, uint price);
    event ListingRemoved(uint indexed propertyId);

    constructor(address _realEstateManager, address _utilityToken) {
        require(_realEstateManager != address(0), "Invalid RealEstateManager address");
        require(_utilityToken != address(0), "Invalid UtilityToken address");
        manager = msg.sender;
        realEstateManager = _realEstateManager;
        utilityToken = IERC20(_utilityToken);
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager can perform this action");
        _;
    }

    modifier onlySeller(uint _propertyId) {
        require(propertyListings[_propertyId].seller == msg.sender, "Only seller can perform this action");
        _;
    }

    function setRentalContract(address _rentalContract) external onlyManager {
        require(_rentalContract != address(0), "RentalContract address cannot be zero");
        require(rentalContract == address(0), "RentalContract address already set");
        rentalContract = _rentalContract;
    }

    function setRealEstateManager(address _realEstateManager) external onlyManager {
        require(_realEstateManager != address(0), "RealEstateManager address cannot be zero");
        realEstateManager = _realEstateManager;
    }

    function setUtilityToken(address _utilityToken) external onlyManager {
        require(_utilityToken != address(0), "UtilityToken address cannot be zero");
        utilityToken = IERC20(_utilityToken);
    }

    // *** CHANGE 2: Added setEscrowAddress function ***
    // Purpose: Allows the manager to set the Escrow contract address once, enabling Marketplace to recognize Escrow
    function setEscrowAddress(address _escrowAddress) external onlyManager {
        require(_escrowAddress != address(0), "Escrow address cannot be zero");
        require(escrowAddress == address(0), "Escrow address already set");
        escrowAddress = _escrowAddress;
    }

    function listProperty(uint _propertyId, uint _price) external {
        require(_price > 0, "Price must be greater than zero");
        uint scaledPrice = _price; // No scaling

        (uint propertyId, , , , address owner, bool isTokenized, , ) = RealEstateManager(realEstateManager).getPropertyDetails(_propertyId);
        require(isTokenized, "Property is not tokenized");
        require(owner == msg.sender, "Caller is not the owner");
        require(!propertyListings[_propertyId].isAvailable, "Property is already listed");

        if (rentalContract != address(0)) {
            RentalContract rental = RentalContract(rentalContract);
            RentalContract.RentalAgreement memory agreement = rental.rentalAgreements(_propertyId);
            require(!agreement.isActive, "Property is currently rented");
        }

        propertyListings[_propertyId] = PropertyListing({
            propertyId: _propertyId,
            price: scaledPrice,
            seller: msg.sender,
            isAvailable: true,
            expirationTimestamp: block.timestamp + 30 days
        });

        emit PropertyListed(_propertyId, msg.sender, scaledPrice);
    }

    // *** CHANGE 3: Fixed PropertySold event emission order ***
    // Purpose: Ensures seller and price are emitted correctly before deleting the listing
    function purchaseProperty(uint _propertyId) external nonReentrant {
        PropertyListing storage listing = propertyListings[_propertyId];
        require(listing.isAvailable, "Property is not available for sale");
        require(block.timestamp <= listing.expirationTimestamp, "Listing has expired");
        require(utilityToken.balanceOf(msg.sender) >= listing.price, "Insufficient token balance");
        require(utilityToken.transferFrom(msg.sender, listing.seller, listing.price), "Token transfer failed. Approve Marketplace first");
        emit PropertySold(_propertyId, listing.seller, msg.sender, listing.price); // Moved up to fix bug
        delete propertyListings[_propertyId];
        RealEstateManager(realEstateManager).transferPropertyOwnershipByMarketplace(_propertyId, msg.sender);
    }

    function removeListing(uint _propertyId) external onlySeller(_propertyId) {
        PropertyListing storage listing = propertyListings[_propertyId];
        require(listing.isAvailable, "Listing is already inactive");
        listing.isAvailable = false;
        emit ListingRemoved(_propertyId);
    }

    // *** CHANGE 4: Added completeEscrowPurchase function ***
    // Purpose: Allows Escrow to delegate property transfer and listing removal, satisfying RealEstateManager's onlyMarketplace modifier
    function completeEscrowPurchase(uint _propertyId, address _newOwner) external {
        require(msg.sender == escrowAddress, "Only escrow can call");
        RealEstateManager(realEstateManager).transferPropertyOwnershipByMarketplace(_propertyId, _newOwner);
        delete propertyListings[_propertyId];
    }

    function getPropertyListing(uint _propertyId) external view returns (uint, uint, address, bool) {
        PropertyListing memory listing = propertyListings[_propertyId];
        return (listing.propertyId, listing.price, listing.seller, listing.isAvailable);
    }
}

interface RealEstateManager {
    function getPropertyDetails(uint _propertyId) external view returns (uint, string memory, string memory, uint, address, bool, bool, address);
    function transferPropertyOwnershipByMarketplace(uint _propertyId, address _newOwner) external;
}

interface RentalContract {
    struct RentalAgreement {
        uint propertyId;
        uint rentalPrice;
        address landlord;
        address tenant;
        uint startDate;
        uint endDate;
        bool isActive;
        uint totalRentCollected;
    }
    function rentalAgreements(uint _propertyId) external view returns (RentalAgreement memory);
}