// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Interface for UtilityToken, assuming it has a mintForProperty function
interface UtilityToken is IERC20 {
    function mintForProperty(uint _propertyId, address _to, uint256 _amount) external;
    function burn(uint256 _amount) external;
}

// @notice This contract is part of a real estate tokenization platform, allowing properties to be added, verified, tokenized, and managed. It integrates with UtilityToken for token issuance, Marketplace for property sales, and RentalContract for property rentals.
/// @dev This contract uses OpenZeppelin's ReentrancyGuard to prevent reentrancy attacks. It is designed to be administered by an admin and managed by a manager, with specific functions restricted to these roles. Properties are stored in a consolidated Property struct to optimize gas usage.
contract RealEstateManager is ReentrancyGuard {


    // Original RealEstateManager properties
    address public admin; //The address of the admin, who has full control over admin-only functions
    address public manager; // he address of the manager, who can perform manager-only functions
    uint public propertyCount; // The total number of properties added to the contract
    address public marketplace; // Address of the Marketplace contract
    address public rentalContract; // Address of the RentalContract
   
    uint decimal = 10**18; //The scaling factor for token amounts (10^18, similar to wei for ETH)


//@dev This struct consolidates all property-related data to optimize gas usage
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

    mapping(uint => Property) public properties; //Mapping from property ID to Property struct, storing all property data
    mapping(address => uint[]) public userProperties; //Mapping from user address to an array of property IDs they own

    // Events 
    event PropertyAdded(uint indexed _propertyId, address indexed _currentOwner, string propertyName);
    event PropertyVerified(uint indexed _propertyId, address indexed verifier);
    event PropertyUnverified(uint indexed _propertyId, address indexed Unverifier);
    event PropertyDetailsUpdated(uint indexed propertyId, string newPropertyName, string newLocation, uint newValue);
    event PropertyOwnershipTransferred(uint indexed _propertyId, address indexed oldOwner, address indexed newOwner, uint tokenAmount);
    event PropertyDeleted(uint indexed _propertyId);
    event RoleRevoked(address indexed _user);
    event PropertyTokenized(uint indexed propertyId, address indexed owner, uint tokenAmount);

    /// @notice The IERC20 interface for the UtilityToken contract, used for token interactions
    IERC20 public utilityToken; // for referencing 




    // Constructors and modifiers 
    /// @notice Constructor to initialize the contract with the UtilityToken address
    /// @param _utilityToken The address of the UtilityToken contract
    /// @dev Inherits ReentrancyGuard to prevent reentrancy attacks
    constructor(address _utilityToken) ReentrancyGuard() {
        admin = msg.sender;
        manager = msg.sender;
        utilityToken = IERC20(_utilityToken);
    }



    /// @notice Modifier to restrict function access to the admin only
    /// @dev Reverts if the caller is not the admin
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    /// @notice Modifier to restrict function access to the manager only
    /// @dev Reverts if the caller is not the manager
    modifier onlyManager() {
        require(msg.sender == manager, "Only the manager can perform this function");
        _;
    }


    /// @notice Modifier to restrict function access to the Marketplace contract only
    /// @dev Reverts if the caller is not the Marketplace contract
    modifier onlyMarketplace() {
        require(msg.sender == marketplace, "Only the marketplace can perform this action");
        _;
    }






    // Function to set the Marketplace address (call after deploying Marketplace)
    // @dev Can only be called by the admin and only once (to prevent overwriting)
    function setMarketplace(address _marketplace) external onlyAdmin {
        require(_marketplace != address(0), "Marketplace address cannot be zero");
        require(marketplace == address(0), "Marketplace address already set");
        marketplace = _marketplace;
    }

    // Function to set the RentalContract address (call after deploying RentalContract)
    // @dev Can only be called by the admin and only once (to prevent overwriting)
    function setRentalContract(address _rentalContract) external onlyAdmin {
        require(_rentalContract != address(0), "RentalContract address cannot be zero");
        require(rentalContract == address(0), "RentalContract address already set");
        rentalContract = _rentalContract;
    }



    /// @notice Adds a new property to the contract
    /// @param _location The location of the property
    /// @param _propertyName The name of the property
    /// @param _value The value of the property in some currency
    /// @param _currentOwner The address of the property’s initial owner
    /// @return The ID of the newly added property
    /// @dev Can only be called by the admin. Initializes tokenAmount to 0 for non-tokenized properties.
    function addProperty(
        string memory _location,
        string memory _propertyName,  
        uint _value,
        address _currentOwner
    ) public onlyAdmin returns(uint) {
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
            tokenAmount: 0 // Initialize tokenAmount to 0
        });

        userProperties[_currentOwner].push(propertyCount);

        emit PropertyAdded(propertyCount, _currentOwner, _propertyName);

        return propertyCount;
    }



    /// @notice Deletes a property from the contract
    /// @param _propertyId The ID of the property to delete
    /// @dev Can only be called by the admin. Burns tokens if the property is tokenized.

    function deleteProperty(uint _propertyId) public onlyAdmin {
    require(properties[_propertyId].propertyId != 0, "Property does not exist");
    if (properties[_propertyId].isTokenized) {
        UtilityToken utilityTokenInterface = UtilityToken(address(utilityToken));
        utilityTokenInterface.burn(properties[_propertyId].tokenAmount); // Use properties instead of tokenizedProperties
    }


    address owner = properties[_propertyId].currentOwner;
    delete properties[_propertyId];
    removePropertyFromUser(owner, _propertyId);
    emit PropertyDeleted(_propertyId);
    }



    /// @notice Verifies a property, marking it as verified
    /// @param _propertyId The ID of the property to verify
    /// @dev Can only be called by the admin. Reverts if the property is already verified.

    function verifyProperty(uint _propertyId) public onlyAdmin {
        require(properties[_propertyId].propertyId != 0, "Property does not exist");
        require(!properties[_propertyId].isVerified, "Property is already verified");

        properties[_propertyId].isVerified = true;
        properties[_propertyId].verifiedBy = msg.sender;

        emit PropertyVerified(_propertyId, msg.sender);
    }



    /// @notice Unverifies a property, revoking its verified status
    /// @param _propertyId The ID of the property to unverify
    /// @dev Can only be called by the admin. Reverts if the property is not verified

    function unverifyProperty(uint _propertyId) public onlyAdmin {
        require(properties[_propertyId].isVerified, "Property is not verified");
        properties[_propertyId].isVerified = false;
        properties[_propertyId].verifiedBy = address(0);

        emit PropertyUnverified(_propertyId, msg.sender);
    }



    /// @notice Checks if a property is verified
    /// @param _propertyId The ID of the property to check
    /// @return True if the property is verified, false otherwise

    function isPropertyVerified(uint _propertyId) public view returns (bool) {
        return properties[_propertyId].isVerified;
    }


    /// @notice Gets the list of property IDs owned by a user
    /// @param _user The address of the user
    /// @return An array of property IDs owned by the user

    function getUserProperties(address _user) public view returns (uint[] memory) {
        return userProperties[_user];
    }


    /// @notice Transfers ownership of a property to a new owner
    /// @param _propertyId The ID of the property to transfer
    /// @param _newOwner The address of the new owner
    /// @dev Can only be called by the current owner. Prevents transfers if the property is listed for rent.

   function transferPropertyOwnership(uint _propertyId, address _newOwner) public {
    require(properties[_propertyId].propertyId != 0, "Property does not exist");
    require(properties[_propertyId].currentOwner == msg.sender, "Only the current owner can transfer this property");
    require(_newOwner != address(0), "New owner cannot be the zero address");

    // Prevent transfer if the property is listed for rent
    if (rentalContract != address(0)) {
        RentalContract rental = RentalContract(rentalContract);
        RentalContract.RentalAgreement memory agreement = rental.rentalAgreements(_propertyId);
        require(!agreement.isActive, "Property is currently listed for rent");
    }

    address oldOwner = properties[_propertyId].currentOwner;
    properties[_propertyId].currentOwner = _newOwner;

    // Update userProperties with duplicate check
    uint index = findPropertyIndex(oldOwner, _propertyId);
    if (index < userProperties[oldOwner].length) {
        userProperties[oldOwner][index] = userProperties[oldOwner][userProperties[oldOwner].length - 1];
        userProperties[oldOwner].pop();
    }
    if (!isPropertyInUserProperties(_newOwner, _propertyId)) {
        userProperties[_newOwner].push(_propertyId);
    }

    emit PropertyOwnershipTransferred(_propertyId, oldOwner, _newOwner, properties[_propertyId].tokenAmount);
    }

    /// @notice Transfers ownership of a property to a new owner, called by the Marketplace contract
    /// @param _propertyId The ID of the property to transfer
    /// @param _newOwner The address of the new owner
    /// @dev Can only be called by the Marketplace contract. Prevents transfers if the property is listed for rent.

    function transferPropertyOwnershipByMarketplace(uint _propertyId, address _newOwner) external onlyMarketplace {
    require(properties[_propertyId].propertyId != 0, "Property does not exist");
    require(_newOwner != address(0), "New owner cannot be the zero address");

    // Prevent transfer if the property is listed for rent
    if (rentalContract != address(0)) {
        RentalContract rental = RentalContract(rentalContract);
        RentalContract.RentalAgreement memory agreement = rental.rentalAgreements(_propertyId);
        require(!agreement.isActive, "Property is currently listed for rent");
    }

    address oldOwner = properties[_propertyId].currentOwner;
    properties[_propertyId].currentOwner = _newOwner;

    // Update userProperties with duplicate check
    uint index = findPropertyIndex(oldOwner, _propertyId);
    if (index < userProperties[oldOwner].length) {
        userProperties[oldOwner][index] = userProperties[oldOwner][userProperties[oldOwner].length - 1];
        userProperties[oldOwner].pop();
    }
    if (!isPropertyInUserProperties(_newOwner, _propertyId)) {
        userProperties[_newOwner].push(_propertyId);
    }

    emit PropertyOwnershipTransferred(_propertyId, oldOwner, _newOwner, properties[_propertyId].tokenAmount);
    }


    /// @notice Finds the index of a property in a user’s property list
    /// @param _owner The address of the user
    /// @param _propertyId The ID of the property to find
    /// @return The index of the property in the user’s property list, or the length of the list if not found
    /// @dev Internal function used to manage userProperties mapping

    function findPropertyIndex(address _owner, uint _propertyId) internal view returns (uint) {
        uint[] storage ownedProperties = userProperties[_owner];
        for (uint i = 0; i < ownedProperties.length; i++) {
            if (ownedProperties[i] == _propertyId) {
                return i;
            }
        }
        return ownedProperties.length; // If not found, return length to signify no match
    }



     /// @notice Checks if a property is already in a user’s property list
    /// @param _user The address of the user
    /// @param _propertyId The ID of the property to check
    /// @return True if the property is in the user’s property list, false otherwise
    /// @dev Private function used to prevent duplicates in userProperties mapping

    // Helper function to check if a property is already in a user's userProperties
   function isPropertyInUserProperties(address _user, uint256 _propertyId) private view returns (bool) {
    uint256[] storage userPropertiesList = userProperties[_user];
    for (uint256 i = 0; i < userPropertiesList.length; i++) {
        if (userPropertiesList[i] == _propertyId) {
            return true;
        }
    }
    return false;
}


    /// @notice Sets a new manager for the contract
    /// @param _newManager The address of the new manager
    /// @dev Can only be called by the admin
    function setManager(address _newManager) public onlyAdmin {
        require(_newManager != address(0), "New manager address cannot be zero address");
        manager = _newManager;
    }


    /// @notice Transfers admin rights to a new admin
    /// @param _newAdmin The address of the new admin
    /// @dev Can only be called by the current admin

    function transferAdmin(address _newAdmin) public onlyAdmin {
        require(_newAdmin != address(0), "New Admin address cannot be zero");
        admin = _newAdmin;
    }



    /// @notice Gets the current manager’s address
    /// @return The address of the current manager
    function getManager() public view returns (address) {
        return manager;
    }



    /// @notice Updates the details of a property
    /// @param _propertyId The ID of the property to update
    /// @param _propertyName The new name of the property
    /// @param _location The new location of the property
    /// @param _value The new value of the property
    /// @dev Can only be called by the property’s owner or the admin

    function updatePropertyDetails(
        uint _propertyId,
        string memory _propertyName,
        string memory _location,
        uint _value
    ) public {
        require(properties[_propertyId].propertyId != 0, "Property does not exist");
        require(
            properties[_propertyId].currentOwner == msg.sender || msg.sender == admin,
            "Only the owner or admin can update property details"
        );

        properties[_propertyId].propertyName = _propertyName;
        properties[_propertyId].location = _location;
        properties[_propertyId].value = _value;

        emit PropertyDetailsUpdated(_propertyId, _propertyName, _location, _value);
    }



    /// @notice Tokenizes a property, issuing tokens via the UtilityToken contract
    /// @param _propertyId The ID of the property to tokenize
    /// @param _tokenAmount The amount of tokens to issue (unscaled, e.g., 100 for 100 RET)
    /// @dev Can only be called by the admin. Scales the token amount by 10^18 before minting.

   function tokenizeProperty(uint _propertyId, uint _tokenAmount) public onlyAdmin nonReentrant {
    require(_tokenAmount > 0, "Token amount must be greater than zero");
    require(!properties[_propertyId].isTokenized, "Property is already tokenized");
    require(properties[_propertyId].isVerified, "Property must be verified before tokenization");
    require(properties[_propertyId].propertyId != 0, "Property does not exist");

    // Scale token amount
    uint scaledTokenAmount = _tokenAmount * decimal;  // token amount scaling

    // Cast utilityToken to UtilityToken interface
    UtilityToken utilityTokenInterface = UtilityToken(address(utilityToken));
    utilityTokenInterface.mintForProperty(_propertyId, properties[_propertyId].currentOwner, scaledTokenAmount);  // Use mintForProperty to mint utility tokens for the property

    properties[_propertyId].isTokenized = true;
    properties[_propertyId].tokenAmount = scaledTokenAmount; // Set tokenAmount in properties

    emit PropertyTokenized(_propertyId, properties[_propertyId].currentOwner, scaledTokenAmount);
    }


    /// @notice Gets the details of a property
    /// @param _propertyId The ID of the property to query
    /// @return propertyId, propertyName, location, value, currentOwner, isTokenized, isVerified, verifiedBy
    /// @dev Returns data from the properties mapping

    function getPropertyDetails(uint _propertyId) public view returns (uint, string memory, string memory, uint, address, bool, bool, address) {
        Property memory property = properties[_propertyId];
        return (
            property.propertyId,
            property.propertyName,
            property.location,
            property.value,
            property.currentOwner,
            property.isTokenized,
            property.isVerified,
            property.verifiedBy
        );
    }



     /// @notice Checks if a property is tokenized
    /// @param _propertyId The ID of the property to check
    /// @return True if the property is tokenized, false otherwise

    function isPropertyTokenized(uint _propertyId) public view returns (bool) {
        return properties[_propertyId].isTokenized;
    }


     /// @notice Gets the tokenization details of a property
    /// @param _propertyId The ID of the property to query
    /// @return propertyId, tokenAmount, isTokenized, currentOwner
    /// @dev Returns data from the properties mapping, focusing on tokenization details

    function getTokenizedPropertyDetails(uint _propertyId) public view returns (uint, uint, bool, address) {
        Property memory property = properties[_propertyId];
        return (property.propertyId, property.tokenAmount, property.isTokenized, property.currentOwner);
    }
    

     /// @notice Removes a property from a user’s property list
    /// @param _owner The address of the user
    /// @param _propertyId The ID of the property to remove
    /// @dev Private function used to manage userProperties mapping during deletion or transfer

    function removePropertyFromUser(address _owner, uint _propertyId) private {
        uint[] storage ownedProperties = userProperties[_owner];
        for (uint i = 0; i < ownedProperties.length; i++) {
            if (ownedProperties[i] == _propertyId) {
                ownedProperties[i] = ownedProperties[ownedProperties.length - 1];
                ownedProperties.pop();
                break;
            }
        }
    }
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