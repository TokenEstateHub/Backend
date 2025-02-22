// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Escrow is ReentrancyGuard {
    address public admin;
    IERC20 public utilityToken;
    address public realEstateManager;
    address public marketplace;
    address public rentalContract;
    uint public constant ESCROW_TIMEOUT = 7 days;

    enum EscrowType { Purchase, Rental }
    enum EscrowStatus { Pending, Completed, Cancelled, Disputed }

    struct EscrowAgreement {
        uint escrowId;
        EscrowType escrowType;
        uint propertyId;
        address buyerOrTenant;
        address sellerOrLandlord;
        uint amount; // Unscaled RET tokens
        uint createdAt;
        uint expiresAt;
        EscrowStatus status;
    }

    uint public escrowCount;
    mapping(uint => EscrowAgreement) public escrows;

    event EscrowCreated(uint indexed escrowId, EscrowType escrowType, uint propertyId, address buyerOrTenant, address sellerOrLandlord, uint amount);
    event EscrowCompleted(uint indexed escrowId, uint propertyId);
    event EscrowCancelled(uint indexed escrowId, uint propertyId);
    event EscrowDisputed(uint indexed escrowId, uint propertyId);
    event FundsReleased(uint indexed escrowId, address to, uint amount);
    event FundsRefunded(uint indexed escrowId, address to, uint amount);

    constructor(address _utilityToken, address _realEstateManager) {
        require(_utilityToken != address(0), "Invalid UtilityToken address");
        require(_realEstateManager != address(0), "Invalid RealEstateManager address");
        admin = msg.sender;
        utilityToken = IERC20(_utilityToken);
        realEstateManager = _realEstateManager;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    modifier onlyParticipant(uint _escrowId) {
        EscrowAgreement memory escrow = escrows[_escrowId];
        require(msg.sender == escrow.buyerOrTenant || msg.sender == escrow.sellerOrLandlord, "Only participants can perform this action");
        _;
    }

    function setMarketplace(address _marketplace) external onlyAdmin {
        require(_marketplace != address(0), "Marketplace address cannot be zero");
        require(marketplace == address(0), "Marketplace address already set");
        marketplace = _marketplace;
    }

    function setRentalContract(address _rentalContract) external onlyAdmin {
        require(_rentalContract != address(0), "RentalContract address cannot be zero");
        require(rentalContract == address(0), "RentalContract address already set");
        rentalContract = _rentalContract;
    }

    function createPurchaseEscrow(uint _propertyId) external nonReentrant {
        (, uint price, address seller, bool isAvailable) = Marketplace(marketplace).getPropertyListing(_propertyId);
        require(isAvailable, "Property is not listed for sale");
        require(utilityToken.transferFrom(msg.sender, address(this), price), "Token transfer failed. Approve Escrow first");

        (, , , , address owner, bool isTokenized, , ) = RealEstateManager(realEstateManager).getPropertyDetails(_propertyId);
        require(isTokenized, "Property is not tokenized");
        require(owner == seller, "Seller does not own the property");

        escrowCount++;
        escrows[escrowCount] = EscrowAgreement({
            escrowId: escrowCount,
            escrowType: EscrowType.Purchase,
            propertyId: _propertyId,
            buyerOrTenant: msg.sender,
            sellerOrLandlord: seller,
            amount: price,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + ESCROW_TIMEOUT,
            status: EscrowStatus.Pending
        });

        emit EscrowCreated(escrowCount, EscrowType.Purchase, _propertyId, msg.sender, seller, price);
    }

    function createRentalEscrow(uint _propertyId) external nonReentrant {
        RentalContract.RentalAgreement memory rental = RentalContract(rentalContract).rentalAgreements(_propertyId);
        require(rental.isActive && rental.tenant == address(0), "Property is not available for rent");
        require(utilityToken.transferFrom(msg.sender, address(this), rental.rentalPrice), "Token transfer failed. Approve Escrow first");

        (, , , , address owner, bool isTokenized, , ) = RealEstateManager(realEstateManager).getPropertyDetails(_propertyId);
        require(isTokenized, "Property is not tokenized");
        require(owner == rental.landlord, "Landlord does not own the property");

        escrowCount++;
        escrows[escrowCount] = EscrowAgreement({
            escrowId: escrowCount,
            escrowType: EscrowType.Rental,
            propertyId: _propertyId,
            buyerOrTenant: msg.sender,
            sellerOrLandlord: rental.landlord,
            amount: rental.rentalPrice,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + ESCROW_TIMEOUT,
            status: EscrowStatus.Pending
        });

        emit EscrowCreated(escrowCount, EscrowType.Rental, _propertyId, msg.sender, rental.landlord, rental.rentalPrice);
    }

    // *** CHANGE 1: Modified completeEscrow to delegate through Marketplace ***
    // Purpose: Delegates property transfer and listing removal to Marketplace, bypassing direct RealEstateManager call
    function completeEscrow(uint _escrowId) external nonReentrant onlyParticipant(_escrowId) {
        EscrowAgreement storage escrow = escrows[_escrowId];
        require(escrow.status == EscrowStatus.Pending, "Escrow is not pending");

        if (escrow.escrowType == EscrowType.Purchase) {
            Marketplace(marketplace).completeEscrowPurchase(escrow.propertyId, escrow.buyerOrTenant); // Changed to delegate
            require(utilityToken.transfer(escrow.sellerOrLandlord, escrow.amount), "Token transfer to seller failed");
        } else if (escrow.escrowType == EscrowType.Rental) {
            RentalContract rental = RentalContract(rentalContract);
            RentalContract.RentalAgreement memory agreement = rental.rentalAgreements(escrow.propertyId);
            require(agreement.isActive && agreement.tenant == address(0), "Property not available for rent");
            rental.updateRentalAgreement(
                escrow.propertyId,
                escrow.buyerOrTenant,
                block.timestamp,
                block.timestamp + 30 days,
                escrow.amount
            );
            require(utilityToken.transfer(rentalContract, escrow.amount), "Token transfer to RentalContract failed");
        }

        escrow.status = EscrowStatus.Completed;
        emit EscrowCompleted(_escrowId, escrow.propertyId);
        emit FundsReleased(_escrowId, escrow.escrowType == EscrowType.Purchase ? escrow.sellerOrLandlord : rentalContract, escrow.amount);
    }

    function cancelEscrow(uint _escrowId) external nonReentrant onlyParticipant(_escrowId) {
        EscrowAgreement storage escrow = escrows[_escrowId];
        require(escrow.status == EscrowStatus.Pending, "Escrow is not pending");
        require(block.timestamp >= escrow.expiresAt || msg.sender == escrow.sellerOrLandlord, "Can only cancel after timeout or by seller/landlord");

        require(utilityToken.transfer(escrow.buyerOrTenant, escrow.amount), "Token refund failed");
        escrow.status = EscrowStatus.Cancelled;
        emit EscrowCancelled(_escrowId, escrow.propertyId);
        emit FundsRefunded(_escrowId, escrow.buyerOrTenant, escrow.amount);
    }

    function disputeEscrow(uint _escrowId) external onlyParticipant(_escrowId) {
        EscrowAgreement storage escrow = escrows[_escrowId];
        require(escrow.status == EscrowStatus.Pending, "Escrow is not pending");
        escrow.status = EscrowStatus.Disputed;
        emit EscrowDisputed(_escrowId, escrow.propertyId);
    }

    // *** CHANGE 2: Modified resolveDisputedEscrow to delegate through Marketplace ***
    // Purpose: Ensures consistency in dispute resolution by also delegating to Marketplace
    function resolveDisputedEscrow(uint _escrowId, bool releaseToSellerOrLandlord) external onlyAdmin nonReentrant {
        EscrowAgreement storage escrow = escrows[_escrowId];
        require(escrow.status == EscrowStatus.Disputed, "Escrow is not disputed");

        if (releaseToSellerOrLandlord) {
            if (escrow.escrowType == EscrowType.Purchase) {
                Marketplace(marketplace).completeEscrowPurchase(escrow.propertyId, escrow.buyerOrTenant); // Changed to delegate
            }
            require(utilityToken.transfer(escrow.sellerOrLandlord, escrow.amount), "Token transfer to seller/landlord failed");
            emit FundsReleased(_escrowId, escrow.sellerOrLandlord, escrow.amount);
        } else {
            require(utilityToken.transfer(escrow.buyerOrTenant, escrow.amount), "Token refund failed");
            emit FundsRefunded(_escrowId, escrow.buyerOrTenant, escrow.amount);
        }

        escrow.status = EscrowStatus.Completed;
        emit EscrowCompleted(_escrowId, escrow.propertyId);
    }

    function getEscrowDetails(uint _escrowId) external view returns (EscrowAgreement memory) {
        return escrows[_escrowId];
    }
}

interface RealEstateManager {
    function getPropertyDetails(uint _propertyId) external view returns (uint, string memory, string memory, uint, address, bool, bool, address);
    function transferPropertyOwnershipByMarketplace(uint _propertyId, address _newOwner) external;
}

interface Marketplace {
    function getPropertyListing(uint _propertyId) external view returns (uint, uint, address, bool);
    function removeListing(uint _propertyId) external;
    // *** CHANGE 3: Updated Marketplace interface ***
    // Purpose: Adds completeEscrowPurchase to the interface for Escrow to call
    function completeEscrowPurchase(uint _propertyId, address _newOwner) external;
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
    function updateRentalAgreement(uint _propertyId, address _tenant, uint _startDate, uint _endDate, uint _rentAmount) external;
}