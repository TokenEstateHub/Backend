// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface UtilityToken is IERC20 {
    function mintForProperty(uint _propertyId, address _to, uint256 _amount) external;
    function burn(uint256 _amount) external;
}

contract RealEstateManager is ReentrancyGuard {
    address public admin;
    address public marketplace;
    address public rentalContract;
    uint public propertyCount;
    IERC20 public utilityToken;
  

    struct Property {
        uint propertyId;
        string propertyName;
        string location;
        uint value;
        address currentOwner;
        bool isTokenized;
        bool isVerified;
        address verifiedBy;
        uint tokenAmount;
    }

    mapping(uint => Property) public properties;
    mapping(address => mapping(uint => uint)) public userPropertyIndices; // O(1) lookup
    mapping(address => uint[]) public userProperties;

    event PropertyAdded(uint indexed _propertyId, address indexed _currentOwner, string propertyName);
    event PropertyTokenized(uint indexed propertyId, address indexed owner, uint tokenAmount);
    event PropertyDeleted(uint indexed _propertyId);
    event PropertyVerified(uint indexed _propertyId, address indexed verifier);
    event PropertyUnverified(uint indexed _propertyId, address indexed unverifier);
    event PropertyDetailsUpdated(uint indexed propertyId, string newPropertyName, string newLocation, uint newValue);
    event PropertyOwnershipTransferred(uint indexed _propertyId, address indexed oldOwner, address indexed newOwner, uint tokenAmount);

    constructor(address _utilityToken) {
        require(_utilityToken != address(0), "Invalid UtilityToken address");
        admin = msg.sender;
        utilityToken = IERC20(_utilityToken);
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    modifier onlyMarketplace() {
        require(msg.sender == marketplace, "Only marketplace can perform this action");
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

    function setUtilityToken(address _utilityToken) external onlyAdmin {
        require(_utilityToken != address(0), "UtilityToken address cannot be zero");
        utilityToken = IERC20(_utilityToken);
    }

    function addProperty(
        string memory _location,
        string memory _propertyName,
        uint _value,
        address _currentOwner
    ) public onlyAdmin returns (uint) {
        require(bytes(_location).length > 0, "Property location cannot be empty");
        require(_value > 0, "Property value must be greater than zero");
        require(bytes(_propertyName).length > 0, "Property Name cannot be empty");
        require(_currentOwner != address(0), "Invalid owner address");

        propertyCount++;
        properties[propertyCount] = Property({
            propertyId: propertyCount,
            propertyName: _propertyName,
            location: _location,
            value: _value,
            currentOwner: _currentOwner,
            isTokenized: false,
            isVerified: false,
            verifiedBy: address(0),
            tokenAmount: 0
        });

        uint[] storage userProps = userProperties[_currentOwner];
        userPropertyIndices[_currentOwner][propertyCount] = userProps.length;
        userProps.push(propertyCount);

        emit PropertyAdded(propertyCount, _currentOwner, _propertyName);
        return propertyCount;
    }

    function deleteProperty(uint _propertyId) public onlyAdmin nonReentrant {
        Property memory prop = properties[_propertyId];
        require(prop.propertyId != 0, "Property does not exist");

        if (rentalContract != address(0)) {
            RentalContract rental = RentalContract(rentalContract);
            RentalContract.RentalAgreement memory agreement = rental.rentalAgreements(_propertyId);
            require(!agreement.isActive, "Property is currently rented");
        }
        if (marketplace != address(0)) {
            (, , , bool isAvailable) = Marketplace(marketplace).getPropertyListing(_propertyId);
            require(!isAvailable, "Property is listed for sale");
        }

        if (prop.isTokenized) {
            require(utilityToken.balanceOf(address(this)) >= prop.tokenAmount, "Insufficient tokens to burn");
            UtilityToken(address(utilityToken)).burn(prop.tokenAmount);
        }

        address owner = prop.currentOwner;
        delete properties[_propertyId];
        removePropertyFromUser(owner, _propertyId);
        emit PropertyDeleted(_propertyId);
    }

    function verifyProperty(uint _propertyId) public onlyAdmin {
        Property storage prop = properties[_propertyId];
        require(prop.propertyId != 0, "Property does not exist");
        require(!prop.isVerified, "Property is already verified");

        prop.isVerified = true;
        prop.verifiedBy = msg.sender;
        emit PropertyVerified(_propertyId, msg.sender);
    }

    function unverifyProperty(uint _propertyId) public onlyAdmin {
        Property storage prop = properties[_propertyId];
        require(prop.propertyId != 0, "Property does not exist");
        require(prop.isVerified, "Property is not verified");

        prop.isVerified = false;
        prop.verifiedBy = address(0);
        emit PropertyUnverified(_propertyId, msg.sender);
    }

    function tokenizeProperty(uint _propertyId, uint _tokenAmount) public onlyAdmin nonReentrant {
        Property storage prop = properties[_propertyId];
        require(_tokenAmount > 0, "Token amount must be greater than zero");
        require(!prop.isTokenized, "Property is already tokenized");
        require(prop.isVerified, "Property must be verified");
        require(prop.propertyId != 0, "Property does not exist");

        uint scaledTokenAmount = _tokenAmount;
        UtilityToken(address(utilityToken)).mintForProperty(_propertyId, prop.currentOwner, scaledTokenAmount);

        prop.isTokenized = true;
        prop.tokenAmount = scaledTokenAmount;
        emit PropertyTokenized(_propertyId, prop.currentOwner, scaledTokenAmount);
    }

    function transferPropertyOwnership(uint _propertyId, address _newOwner) public {
        Property storage prop = properties[_propertyId];
        require(prop.propertyId != 0, "Property does not exist");
        require(prop.currentOwner == msg.sender, "Only current owner can transfer");
        require(_newOwner != address(0), "New owner cannot be zero address");

        if (rentalContract != address(0)) {
            RentalContract rental = RentalContract(rentalContract);
            RentalContract.RentalAgreement memory agreement = rental.rentalAgreements(_propertyId);
            require(!agreement.isActive, "Property is currently rented");
        }

        address oldOwner = prop.currentOwner;
        prop.currentOwner = _newOwner;
        updateUserProperties(oldOwner, _newOwner, _propertyId);
        emit PropertyOwnershipTransferred(_propertyId, oldOwner, _newOwner, prop.tokenAmount);
    }

    function transferPropertyOwnershipByMarketplace(uint _propertyId, address _newOwner) external onlyMarketplace {
        Property storage prop = properties[_propertyId];
        require(prop.propertyId != 0, "Property does not exist");
        require(_newOwner != address(0), "New owner cannot be zero address");

        if (rentalContract != address(0)) {
            RentalContract rental = RentalContract(rentalContract);
            RentalContract.RentalAgreement memory agreement = rental.rentalAgreements(_propertyId);
            require(!agreement.isActive, "Property is currently rented");
        }

        address oldOwner = prop.currentOwner;
        prop.currentOwner = _newOwner;
        updateUserProperties(oldOwner, _newOwner, _propertyId);
        emit PropertyOwnershipTransferred(_propertyId, oldOwner, _newOwner, prop.tokenAmount);
    }

    function updatePropertyDetails(uint _propertyId, string memory _propertyName, string memory _location, uint _value) public {
        Property storage prop = properties[_propertyId];
        require(prop.propertyId != 0, "Property does not exist");
        require(prop.currentOwner == msg.sender || msg.sender == admin, "Only owner or admin can update");

        prop.propertyName = _propertyName;
        prop.location = _location;
        prop.value = _value;
        emit PropertyDetailsUpdated(_propertyId, _propertyName, _location, _value);
    }

    function withdrawETH() public onlyAdmin {
        uint balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        (bool success, ) = payable(admin).call{value: balance}("");
        require(success, "ETH withdrawal failed");
    }

    function getPropertyDetails(uint _propertyId) public view returns (uint, string memory, string memory, uint, address, bool, bool, address) {
        Property memory prop = properties[_propertyId];
        return (prop.propertyId, prop.propertyName, prop.location, prop.value, prop.currentOwner, prop.isTokenized, prop.isVerified, prop.verifiedBy);
    }

    function getUserProperties(address _user) public view returns (uint[] memory) {
        return userProperties[_user];
    }

    function isPropertyVerified(uint _propertyId) public view returns (bool) {
        return properties[_propertyId].isVerified;
    }

    function isPropertyTokenized(uint _propertyId) public view returns (bool) {
        return properties[_propertyId].isTokenized;
    }

    function getTokenizedPropertyDetails(uint _propertyId) public view returns (uint, uint, bool, address) {
        Property memory prop = properties[_propertyId];
        return (prop.propertyId, prop.tokenAmount, prop.isTokenized, prop.currentOwner);
    }

    function updateUserProperties(address _oldOwner, address _newOwner, uint _propertyId) private {
        uint[] storage oldProps = userProperties[_oldOwner];
        uint index = userPropertyIndices[_oldOwner][_propertyId];
        if (index < oldProps.length && oldProps[index] == _propertyId) {
            oldProps[index] = oldProps[oldProps.length - 1];
            userPropertyIndices[_oldOwner][oldProps[index]] = index;
            oldProps.pop();
            delete userPropertyIndices[_oldOwner][_propertyId];
        }

        uint[] storage newProps = userProperties[_newOwner];
        if (!isPropertyInUserProperties(_newOwner, _propertyId)) {
            userPropertyIndices[_newOwner][_propertyId] = newProps.length;
            newProps.push(_propertyId);
        }
    }

    function removePropertyFromUser(address _owner, uint _propertyId) private {
        uint[] storage props = userProperties[_owner];
        uint index = userPropertyIndices[_owner][_propertyId];
        if (index < props.length && props[index] == _propertyId) {
            props[index] = props[props.length - 1];
            userPropertyIndices[_owner][props[index]] = index;
            props.pop();
            delete userPropertyIndices[_owner][_propertyId];
        }
    }

    function isPropertyInUserProperties(address _user, uint _propertyId) private view returns (bool) {
        return userPropertyIndices[_user][_propertyId] < userProperties[_user].length && 
               userProperties[_user][userPropertyIndices[_user][_propertyId]] == _propertyId;
    }
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
    }

    function rentalAgreements(uint _propertyId) external view returns (RentalAgreement memory);
}

interface Marketplace {
    function getPropertyListing(uint _propertyId) external view returns (uint, uint, address, bool);
}