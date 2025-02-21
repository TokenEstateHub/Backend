// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Interface for RealEstateManager
interface RealEstateManager {
    function getPropertyDetails(uint _propertyId) external view returns (
        uint, string memory, string memory, uint, address, bool, bool, address
    );
}

// Interface for UtilityToken
interface UtilityToken is IERC20 {
    function distributeYield(uint256 _propertyId, uint256 _totalYieldInTokens) external;
}

// Interface for Marketplace
interface Marketplace {
    function getPropertyListing(uint _propertyId) external view returns (uint, uint, address, bool);
}

contract RentalContract is ReentrancyGuard {
    address public manager; // Manager address for admin functions
    address public admin; 
    IERC20 public utilityToken; // Utility token for rental payments
    address public realEstateManager; // RealEstateManager address
    address public marketplace; // Marketplace address to check for sale listings

    struct RentalAgreement {
        uint propertyId;
        uint rentalPrice; // Monthly rental price in utility tokens
        address landlord;
        address tenant;
        uint startDate;
        uint endDate;
        bool isActive;
    }

    mapping(uint => RentalAgreement) public rentalAgreements; // Maps property IDs to rental agreements

    event PropertyListedForRent(uint indexed propertyId, address indexed landlord, uint rentalPrice);
    event RentalPaymentMade(uint indexed propertyId, address indexed tenant, uint amount);
    event RentalIncomeDistributed(uint indexed propertyId, address indexed landlord, uint totalIncome);
    event RentalAgreementEnded(uint indexed propertyId);
    event RentalAgreementRenewed(uint indexed propertyId, uint newEndDate);

    modifier onlyManager() {
        require(msg.sender == manager, "Only the manager can perform this action");
        _;
    }

    modifier onlyLandlord(uint _propertyId) {
        require(rentalAgreements[_propertyId].landlord == msg.sender, "Only the landlord can perform this action");
        _;
    }

    modifier onlyTenant(uint _propertyId) {
        require(rentalAgreements[_propertyId].tenant == msg.sender, "Only the tenant can perform this action");
        _;
    }

    constructor(address _utilityToken, address _realEstateManager) {
        require(_utilityToken != address(0), "Invalid UtilityToken address");
        require(_realEstateManager != address(0), "Invalid RealEstateManager address");

        utilityToken = IERC20(_utilityToken);
        realEstateManager = _realEstateManager;
        manager = msg.sender;
        admin = msg.sender;
    }

    // Function to set the Marketplace address (call after deploying Marketplace)
    function setMarketplace(address _marketplace) external onlyManager {
        require(_marketplace != address(0), "Marketplace address cannot be zero");
        require(marketplace == address(0), "Marketplace address already set");
        marketplace = _marketplace;
    }

    /// @notice Lists a property for rent.
    /// @param _propertyId The ID of the property to list.
    /// @param _rentalPrice The monthly rental price in UtilityToken (RET) tokens.
    function listForRent(uint _propertyId, uint _rentalPrice) external {
        require(_rentalPrice > 0, "Rental price must be greater than zero");
        require(!rentalAgreements[_propertyId].isActive, "Property is already listed for rent");

        // Verify property exists and is tokenized via RealEstateManager
        (uint propertyId, , , , address owner, bool isTokenized, , ) = RealEstateManager(realEstateManager).getPropertyDetails(_propertyId);
        require(propertyId != 0, "Property does not exist");
        require(isTokenized, "Property is not tokenized");
        require(owner == msg.sender, "Caller is not the owner");

        // Check if the property is listed for sale in Marketplace
        if (marketplace != address(0)) {
            (, , , bool isAvailable) = Marketplace(marketplace).getPropertyListing(_propertyId);
            require(!isAvailable, "Property is already listed for sale");
        }

        // Create a rental agreement
        rentalAgreements[_propertyId] = RentalAgreement({
            propertyId: _propertyId,
            rentalPrice: _rentalPrice,
            landlord: msg.sender,
            tenant: address(0),
            startDate: 0,
            endDate: 0,
            isActive: true
        });

        emit PropertyListedForRent(_propertyId, msg.sender, _rentalPrice);
    }

    /// @notice Rents a property, transferring the first month's rent.
    /// @param _propertyId The ID of the property to rent.
    /// @dev Ensure you have approved the RentalContract to spend your tokens via UtilityToken.approve().
    function rentProperty(uint _propertyId) external nonReentrant {
        RentalAgreement storage agreement = rentalAgreements[_propertyId];
        require(agreement.isActive, "Property is not available for rent");
        require(agreement.tenant == address(0), "Property is already rented");

        // Transfer the first month's rent from the tenant to the contract
        require(utilityToken.transferFrom(msg.sender, address(this), agreement.rentalPrice), "Rental payment failed");

        // Update the rental agreement
        agreement.tenant = msg.sender;
        agreement.startDate = block.timestamp;
        agreement.endDate = block.timestamp + 30 days; // 1-month rental period

        emit RentalPaymentMade(_propertyId, msg.sender, agreement.rentalPrice);
    }

    /// @notice Distributes rental income to fractional owners of the property.
    /// @param _propertyId The ID of the property.
    function distributeRentalIncome(uint _propertyId) external nonReentrant {
        RentalAgreement storage agreement = rentalAgreements[_propertyId];
        require(agreement.isActive, "Rental agreement is not active");
        require(block.timestamp >= agreement.endDate, "Rental period has not ended");

        // Calculate total rental income
        uint totalIncome = agreement.rentalPrice;

        // Distribute income to fractional owners via UtilityToken
        UtilityToken(address(utilityToken)).distributeYield(_propertyId, totalIncome);

        // End the rental agreement
        agreement.isActive = false;
        agreement.tenant = address(0);

        emit RentalIncomeDistributed(_propertyId, agreement.landlord, totalIncome);
        emit RentalAgreementEnded(_propertyId);
    }

    /// @notice Ends a rental agreement early, only callable by the landlord.
    /// @param _propertyId The ID of the property.
    function endRentalAgreement(uint _propertyId) external onlyLandlord(_propertyId) {
        RentalAgreement storage agreement = rentalAgreements[_propertyId];
        require(agreement.isActive, "Rental agreement is not active");

        // End the rental agreement
        agreement.isActive = false;
        agreement.tenant = address(0);

        emit RentalAgreementEnded(_propertyId);
    }

    /// @notice Renews a rental agreement, extending the rental period.
    /// @param _propertyId The ID of the property.
    /// @dev Ensure you have approved the RentalContract to spend your tokens via UtilityToken.approve().
    function renewRentalAgreement(uint _propertyId) external onlyTenant(_propertyId) nonReentrant {
        RentalAgreement storage agreement = rentalAgreements[_propertyId];
        require(agreement.isActive, "Rental agreement is not active");
        require(block.timestamp >= agreement.endDate, "Rental period has not ended");

        // Transfer the next month's rent from the tenant to the contract
        require(utilityToken.transferFrom(msg.sender, address(this), agreement.rentalPrice), "Rental payment failed");

        // Extend the rental agreement
        agreement.startDate = block.timestamp;
        agreement.endDate = block.timestamp + 30 days; // Extend by 1 month

        emit RentalPaymentMade(_propertyId, msg.sender, agreement.rentalPrice);
        emit RentalAgreementRenewed(_propertyId, agreement.endDate);
    }
}

