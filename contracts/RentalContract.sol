// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RentalContract is ReentrancyGuard {
    address public manager;
    IERC20 public utilityToken;
    address public realEstateManager;
    address public marketplace;
    // *** CHANGE 1: Added escrowAddress state variable ***
    // Purpose: Stores the Escrow contract address to allow it to call updateRentalAgreement
    address public escrowAddress;

    struct RentalAgreement {
        uint propertyId;
        uint rentalPrice; // Unscaled RET tokens
        address landlord;
        address tenant;
        uint startDate;
        uint endDate;
        bool isActive;
        uint totalRentCollected; // Unscaled RET tokens
    }

    mapping(uint => RentalAgreement) public rentalAgreements;

    event PropertyListedForRent(uint indexed propertyId, address indexed landlord, uint rentalPrice);
    event RentalPaymentMade(uint indexed propertyId, address indexed tenant, uint amount);
    event RentalIncomeDistributed(uint indexed propertyId, address indexed landlord, uint totalIncome);
    event RentalAgreementEnded(uint indexed propertyId);

    constructor(address _utilityToken, address _realEstateManager) {
        require(_utilityToken != address(0), "Invalid UtilityToken address");
        require(_realEstateManager != address(0), "Invalid RealEstateManager address");
        utilityToken = IERC20(_utilityToken);
        realEstateManager = _realEstateManager;
        manager = msg.sender;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager can perform this action");
        _;
    }

    modifier onlyLandlord(uint _propertyId) {
        require(rentalAgreements[_propertyId].landlord == msg.sender, "Only landlord can perform this action");
        _;
    }

    modifier onlyTenant(uint _propertyId) {
        require(rentalAgreements[_propertyId].tenant == msg.sender, "Only tenant can perform this action");
        _;
    }

    function setMarketplace(address _marketplace) external onlyManager {
        require(_marketplace != address(0), "Marketplace address cannot be zero");
        require(marketplace == address(0), "Marketplace address already set");
        marketplace = _marketplace;
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
    // Purpose: Allows the manager to set the Escrow contract address, enabling Escrow to interact with this contract
    function setEscrowAddress(address _escrowAddress) external onlyManager {
        require(_escrowAddress != address(0), "Escrow address cannot be zero");
        require(escrowAddress == address(0), "Escrow address already set");
        escrowAddress = _escrowAddress;
    }

    function listForRent(uint _propertyId, uint _rentalPrice, uint _duration) external {
        require(_rentalPrice > 0, "Rental price must be greater than zero");
        require(_duration > 0, "Duration must be greater than zero");
        require(!rentalAgreements[_propertyId].isActive, "Property is already rented");

        (uint propertyId, , , , address owner, bool isTokenized, , ) = RealEstateManager(realEstateManager).getPropertyDetails(_propertyId);
        require(isTokenized, "Property is not tokenized");
        require(owner == msg.sender, "Caller is not the owner");

        if (marketplace != address(0)) {
            (, , , bool isAvailable) = Marketplace(marketplace).getPropertyListing(_propertyId);
            require(!isAvailable, "Property is listed for sale");
        }

        uint scaledPrice = _rentalPrice; // No scaling in this ecosystem
        rentalAgreements[_propertyId] = RentalAgreement({
            propertyId: _propertyId,
            rentalPrice: scaledPrice,
            landlord: msg.sender,
            tenant: address(0),
            startDate: 0,
            endDate: 0,
            isActive: true,
            totalRentCollected: 0
        });

        emit PropertyListedForRent(_propertyId, msg.sender, scaledPrice);
    }

    function rentProperty(uint _propertyId) external nonReentrant {
        RentalAgreement storage agreement = rentalAgreements[_propertyId];
        require(agreement.isActive, "Property is not available for rent");
        require(agreement.tenant == address(0), "Property is already rented");

        require(utilityToken.balanceOf(msg.sender) >= agreement.rentalPrice, "Insufficient token balance");
        uint balanceBefore = utilityToken.balanceOf(address(this));
        require(utilityToken.balanceOf(address(this)) >= balanceBefore + agreement.rentalPrice, "Send tokens to contract first");

        agreement.tenant = msg.sender;
        agreement.startDate = block.timestamp;
        agreement.endDate = block.timestamp + 30 days;
        agreement.totalRentCollected += agreement.rentalPrice;

        emit RentalPaymentMade(_propertyId, msg.sender, agreement.rentalPrice);
    }

    function distributeRentalIncome(uint _propertyId) external nonReentrant {
        RentalAgreement storage agreement = rentalAgreements[_propertyId];
        require(agreement.isActive, "Rental agreement is not active");
        require(block.timestamp >= agreement.endDate, "Rental period has not ended");

        uint totalIncome = agreement.totalRentCollected;
        require(totalIncome > 0, "No rent collected");

        UtilityToken(address(utilityToken)).distributeYield(_propertyId, totalIncome);
        agreement.isActive = false;
        agreement.tenant = address(0);
        agreement.totalRentCollected = 0;

        emit RentalIncomeDistributed(_propertyId, agreement.landlord, totalIncome);
        emit RentalAgreementEnded(_propertyId);
    }

    function endRentalAgreement(uint _propertyId) external onlyLandlord(_propertyId) {
        RentalAgreement storage agreement = rentalAgreements[_propertyId];
        require(agreement.isActive, "Rental agreement is not active");

        agreement.isActive = false;
        agreement.tenant = address(0);
        emit RentalAgreementEnded(_propertyId);
    }

    function renewRentalAgreement(uint _propertyId) external onlyTenant(_propertyId) nonReentrant {
        RentalAgreement storage agreement = rentalAgreements[_propertyId];
        require(agreement.isActive, "Rental agreement is not active");
        require(block.timestamp >= agreement.endDate, "Rental period has not ended");

        require(utilityToken.balanceOf(msg.sender) >= agreement.rentalPrice, "Insufficient token balance");
        uint balanceBefore = utilityToken.balanceOf(address(this));
        require(utilityToken.balanceOf(address(this)) >= balanceBefore + agreement.rentalPrice, "Send tokens to contract first");

        agreement.startDate = block.timestamp;
        agreement.endDate = block.timestamp + 30 days;
        agreement.totalRentCollected += agreement.rentalPrice;

        emit RentalPaymentMade(_propertyId, msg.sender, agreement.rentalPrice);
    }

    // *** CHANGE 3: Modified updateRentalAgreement access control ***
    // Purpose: Allows the Escrow contract (via escrowAddress) to call this function, enabling escrow-based rental completion
    function updateRentalAgreement(uint _propertyId, address _tenant, uint _startDate, uint _endDate, uint _rentAmount) external {
        require(msg.sender == escrowAddress || msg.sender == manager, "Only escrow or manager can call"); // Updated from address(this) to escrowAddress
        RentalAgreement storage agreement = rentalAgreements[_propertyId];
        require(agreement.isActive, "Rental agreement is not active");
        require(agreement.tenant == address(0), "Property is already rented");

        agreement.tenant = _tenant;
        agreement.startDate = _startDate;
        agreement.endDate = _endDate;
        agreement.totalRentCollected += _rentAmount;

        emit RentalPaymentMade(_propertyId, _tenant, _rentAmount);
    }
}

interface RealEstateManager {
    function getPropertyDetails(uint _propertyId) external view returns (uint, string memory, string memory, uint, address, bool, bool, address);
}

interface UtilityToken is IERC20 {
    function distributeYield(uint256 _propertyId, uint256 _totalYieldInTokens) external;
}

interface Marketplace {
    function getPropertyListing(uint _propertyId) external view returns (uint, uint, address, bool);
}