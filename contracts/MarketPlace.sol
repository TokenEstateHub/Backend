// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

//@title Marketplace - A contract for listing, selling, and managing tokenized real estate properties
//@notice This contract is part of a real estate tokenization platform, enabling users to list tokenized properties for sale, purchase properties using UtilityToken (RET), and manage listings. It integrates with RealEstateManager for property data and ownership transfers, and RentalContract to prevent conflicts with rental listings.
contract Marketplace is ReentrancyGuard {


    
    address public manager; // Manager address for admin functions
    address public realEstateManager; // Address of the RealEstateManager contract
    address public rentalContract; // Address of the RentalContract
    IERC20 public utilityToken; // Interface for interacting with UtilityToken contract
    
    struct PropertyListing {
        uint propertyId; //ID of the property being listed 
        uint price; // Price in UtilityToken , scaled by 10**18
        address seller;//current address of the seller (current owner)
        bool isAvailable; // whether the listing is active and available for purchase 
    }


    /// @notice Mapping from property ID to PropertyListing struct, storing all listing data
    mapping(uint => PropertyListing) public propertyListings; // Maps property IDs to listings


    //Events
    event PropertyListed(uint indexed propertyId, address indexed seller, uint price);
    event PropertySold(uint indexed propertyId, address indexed seller, address indexed buyer, uint price);
    event ListingRemoved(uint indexed propertyId);



    /// @notice Modifier to restrict function access to the manager only
    /// @dev Reverts if the caller is not the manager
    modifier onlyManager() {
        require(msg.sender == manager, "Only the manager can perform this action");
        _;
    }


    /// @notice Modifier to restrict function access to the seller of a specific property listing
    /// @param _propertyId The ID of the property listing
    /// @dev Reverts if the caller is not the seller of the specified property

    modifier onlySeller(uint _propertyId) {
        require(propertyListings[_propertyId].seller == msg.sender, "Only the seller can perform this action");
        _;
    }



    /// @notice Constructor to initialize the contract with RealEstateManager and UtilityToken addresses
    /// @param _realEstateManager The address of the RealEstateManager contract
    /// @param _utilityToken The address of the UtilityToken contract
    /// @dev Sets the manager to the deployer and initializes contract dependencies
    constructor(address _realEstateManager, address _utilityToken) {
        manager = msg.sender;
        realEstateManager = _realEstateManager;
        utilityToken = IERC20(_utilityToken);
    }



    /// @notice Sets the address of the RentalContract
    /// @param _rentalContract The address of the RentalContract
    /// @dev Can only be called by the manager and only once (to prevent overwriting)
    // Function to set the RentalContract address (call after deploying RentalContract)
    function setRentalContract(address _rentalContract) external onlyManager {
        require(_rentalContract != address(0), "RentalContract address cannot be zero");
        require(rentalContract == address(0), "RentalContract address already set");
        rentalContract = _rentalContract;
    }

    /// @notice Lists a property for sale on the marketplace.
    /// @param _propertyId The ID of the property to list.
    /// @param _price The price in UtilityToken (RET) tokens.
    /// @dev Verifies ownership and tokenization via RealEstateManager, checks for rental conflicts via RentalContract, and ensures the property is not already listed

    function listProperty(uint _propertyId, uint _price) external {
        require(_price > 0, "Price must be greater than zero");

        // Verify property exists and is tokenized via RealEstateManager
        (uint propertyId, , , , address owner, bool isTokenized, , ) = RealEstateManager(realEstateManager).getPropertyDetails(_propertyId);
        require(propertyId != 0, "Property does not exist");
        require(isTokenized, "Property is not tokenized");
        require(owner == msg.sender, "Caller is not the owner");
        require(!propertyListings[_propertyId].isAvailable, "Property is already listed");

        // Check if the property is listed for rent in RentalContract
        if (rentalContract != address(0)) {
            RentalContract rental = RentalContract(rentalContract);
            RentalContract.RentalAgreement memory agreement = rental.rentalAgreements(_propertyId);
            require(!agreement.isActive, "Property is currently listed for rent");
        }

        // Create a listing
        propertyListings[_propertyId] = PropertyListing({
            propertyId: _propertyId,
            price: _price,
            seller: msg.sender,
            isAvailable: true
        });

        emit PropertyListed(_propertyId, msg.sender, _price);
    }



    /// @notice Purchases a listed property, transferring tokens and updating ownership
    /// @param _propertyId The ID of the property to purchase
    /// @dev Ensure you have approved the Marketplace contract to spend your tokens via UtilityToken.approve() with the amount scaled by 10^18. Uses nonReentrant to prevent reentrancy attacks.
    function purchaseProperty(uint _propertyId) external nonReentrant {
        PropertyListing storage listing = propertyListings[_propertyId];
        require(listing.isAvailable, "Property is not available for sale");
        
        // Check if buyer has enough tokens
        require(utilityToken.balanceOf(msg.sender) >= listing.price, "Insufficient token balance");

        // Transfer tokens from buyer to seller
        require(utilityToken.transferFrom(msg.sender, listing.seller, listing.price), "Token transfer failed");

        // Update listing status
        listing.isAvailable = false;

        // Update property ownership in RealEstateManager
        RealEstateManager(realEstateManager).transferPropertyOwnershipByMarketplace(_propertyId, msg.sender);

        emit PropertySold(_propertyId, listing.seller, msg.sender, listing.price);
    }

    /// @notice Removes a property listing from the marketplace.
    /// @param _propertyId The ID of the property to remove.
    function removeListing(uint _propertyId) external onlySeller(_propertyId) {
        require(propertyListings[_propertyId].isAvailable, "Listing is already inactive");

        // Remove the listing
        propertyListings[_propertyId].isAvailable = false;

        emit ListingRemoved(_propertyId);
    }

    /// @notice Gets the details of a property listing.
    /// @param _propertyId The ID of the property.
    /// @return propertyId, price, seller, isAvailable
    function getPropertyListing(uint _propertyId) external view returns (uint, uint, address, bool) {
        PropertyListing memory listing = propertyListings[_propertyId];
        return (
            listing.propertyId,
            listing.price,
            listing.seller,
            listing.isAvailable
        );
    }
}

// Interface for RealEstateManager
interface RealEstateManager {
    function getPropertyDetails(uint _propertyId) external view returns (
        uint, string memory, string memory, uint, address, bool, bool, address
    );
    function transferPropertyOwnershipByMarketplace(uint _propertyId, address _newOwner) external;
}

// Interface for RentalContract
interface RentalContract {
    struct RentalAgreement {
        uint propertyId;
        uint rentalPrice;
        address landlord;
        address tenant;
        uint startDate;
        uint endDate;
        bool isActive;
    }

    function rentalAgreements(uint _propertyId) external view returns (RentalAgreement memory);
}