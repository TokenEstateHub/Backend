// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract UtilityToken is ERC20, Ownable, ReentrancyGuard { 

    address public admin; 
    address public manager; 
   
    address public realEstateManager;
    address public marketplace; // Address of the Marketplace contract
    address public rentalContract; // Address of the RentalContract

    address public liquidityPoolAddress;
    address public devFundAddress;
    address public teamAddress;
    address public publicSaleAddress;

    uint256 public constant INITIAL_SUPPLY = 1000000 * 10**18; // 1 million tokens 
    uint public constant DECIMAL = 10**18; // Scaling factor for token amounts, for reference
    mapping(uint256 => uint256) public propertyTotalTokens; // Property ID to total tokens issued 
    mapping(address => uint256[]) public userProperties; // User address to array of property IDs they hold tokens for 
    mapping(uint256 => address) public propertyOwners; // Property ID to current owner
    mapping(uint256 => mapping(address => uint256)) public propertyTokenBalances;
    // New storage to track users per property
    mapping(uint256 => address[]) public propertyTokenHolders; // Property ID => list of token holders
    mapping(uint256 => mapping(address => uint256)) public propertyTokenHolderIndices; // Property ID => user => index in propertyTokenHolders

    event TokensMintedForProperty(uint indexed propertyId, address indexed to, uint amount);
    event YieldDistributed(uint indexed propertyId, uint amount);
    event PropertyOwnershipTransferred(uint indexed propertyId, address indexed oldOwner, address indexed newOwner);
    event RealEstateManagerSet(address indexed realEstateManager);

    // New for Bonding Curve
    uint256 public basePrice = 1e16; // 0.01 ETH per token at start
    uint256 public priceIncreaseRate = 1e12; // Price increase per token minted, in wei (0.000001 ETH)

    // Token distribution addresses
    uint256 private constant TOTAL_SUPPLY = 1_000_000 * 10**18; // Example total supply of 1 million tokens

    // Modifier to restrict access to the RealEstateManager contract
    modifier onlyRealEstateManager() {
        require(msg.sender == realEstateManager, "Only RealEstateManager can call this function");
        _;
    }

    modifier onlySetAddress(address _contractAddress) {
        require(_contractAddress != address(0), "Address not set");
        _; 
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Only the manager can perform this action");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only the Admin can perform this action.....");
        _;
    }

    modifier onlyRentalContract() {
        require(msg.sender == rentalContract, "Only the RentalContract can perform this action");
        _;
    }

    constructor() ERC20("RealEstateToken", "RET") Ownable(msg.sender) {
        manager = msg.sender; 
        admin = msg.sender; // Set the deployer as the initial manager 
    }

    // Function to set addresses after deployment
    function setRealEstateManager(address _realEstateManager) public onlyOwner {
        require(realEstateManager == address(0), "RealEstateManager address already set");
        require(_realEstateManager != address(0), "RealEstateManager address cannot be zero");
        realEstateManager = _realEstateManager; // set realestatemanager for access and permission for minting purposes 
        emit RealEstateManagerSet(_realEstateManager);
    }

    // Function to set the Marketplace address (call after deploying Marketplace)
    function setMarketplace(address _marketplace) public onlyOwner {
        require(_marketplace != address(0), "Marketplace address cannot be zero");
        require(marketplace == address(0), "Marketplace address already set");
        marketplace = _marketplace;
    }

    // Function to set the RentalContract address (call after deploying RentalContract)
    function setRentalContract(address _rentalContract) public onlyOwner {
        require(_rentalContract != address(0), "RentalContract address cannot be zero");
        require(rentalContract == address(0), "RentalContract address already set");
        rentalContract = _rentalContract;
    }

    function setLiquidityPoolAddress(address _liquidityPoolAddress) public onlyOwner {
        require(liquidityPoolAddress == address(0), "LiquidityPool address already set");
        liquidityPoolAddress = _liquidityPoolAddress;
    }

    // Similar functions for other addresses
    function setDevFundAddress(address _devFundAddress) public onlyOwner {
        require(devFundAddress == address(0), "DevFund address already set");
        devFundAddress = _devFundAddress;
    }

    function setTeamAddress(address _teamAddress) public onlyOwner {
        require(teamAddress == address(0), "Team address already set");
        teamAddress = _teamAddress;
    }

    function setPublicSaleAddress(address _publicSaleAddress) public onlyOwner {
        require(publicSaleAddress == address(0), "PublicSale address already set");
        publicSaleAddress = _publicSaleAddress;
    }

    // Function to distribute tokens after setting addresses
    function distributeTokens() public onlyOwner {
        require(realEstateManager != address(0) && liquidityPoolAddress != address(0) 
            && devFundAddress != address(0) && teamAddress != address(0) && publicSaleAddress != address(0), 
            "All addresses must be set before distribution");

        _mint(realEstateManager, TOTAL_SUPPLY * 50 / 100);
        _mint(liquidityPoolAddress, TOTAL_SUPPLY * 20 / 100);
        _mint(devFundAddress, TOTAL_SUPPLY * 10 / 100);
        _mint(teamAddress, TOTAL_SUPPLY * 10 / 100);
        _mint(publicSaleAddress, TOTAL_SUPPLY * 10 / 100);

        require(totalSupply() == TOTAL_SUPPLY, "Total supply mismatch");
    }

    /// @notice Mints tokens for a specific property, restricted to the RealEstateManager.
    /// @param _propertyId The ID of the property.
    /// @param _to The address to receive the tokens.
    /// @param _amount The amount of tokens to mint, scaled by 10**18 (e.g., 1 RET = 1 * 10**18).
    function mintForProperty(uint256 _propertyId, address _to, uint256 _amount) public onlyRealEstateManager {
        require(_to != address(0), "Invalid recipient address");
        require(_amount > 0, "Token amount must be greater than zero");

        propertyTotalTokens[_propertyId] += _amount;
        if (propertyTokenBalances[_propertyId][_to] == 0) { // Only add if this is their first balance
            propertyTokenHolderIndices[_propertyId][_to] = propertyTokenHolders[_propertyId].length;
            propertyTokenHolders[_propertyId].push(_to);
        }
        propertyTokenBalances[_propertyId][_to] += _amount;
        if (!isPropertyInUserProperties(_to, _propertyId)) { // Prevent duplicates in userProperties
            userProperties[_to].push(_propertyId);
        }
        propertyOwners[_propertyId] = _to;
        _mint(_to, _amount);
        
        emit TokensMintedForProperty(_propertyId, _to, _amount);
    }

    // Bonding Curve Functions
    function calculatePrice(uint256 _amount) public   returns (uint256) {
        uint256 currentSupply = totalSupply();
        // Quadratic pricing: price = basePrice + (supply^2 * priceIncreaseRate)
        uint256 averagePrice = basePrice + (currentSupply * currentSupply * priceIncreaseRate) / 1e18;
        return averagePrice * _amount;
    }

    /// @notice Buys tokens using the bonding curve.
    /// @param _amount The amount of tokens to buy, scaled by 10**18 (e.g., 1 RET = 1 * 10**18).
    function buy(uint256 _amount) external payable nonReentrant {
        uint256 totalCost = calculatePrice(_amount);
        require(msg.value >= totalCost, "Insufficient payment");

        // Refund excess ETH if any
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }

        // Ensure we don't mint more than TOTAL_SUPPLY
        require(totalSupply() + _amount <= TOTAL_SUPPLY, "Exceeds total supply");

        _mint(msg.sender, _amount);
    }

    /// @notice Sells tokens back to the contract using the bonding curve.
    /// @param _amount The amount of tokens to sell, scaled by 10**18 (e.g., 1 RET = 1 * 10**18).
    function sell(uint256 _amount) external nonReentrant {
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");

        uint256 totalRefund = calculatePrice(_amount); // Use the same pricing mechanism for selling
        require(address(this).balance >= totalRefund, "Insufficient contract balance for redemption");

        _burn(msg.sender, _amount);
        payable(msg.sender).transfer(totalRefund);
    }

    /// @notice Burns tokens from the contract's balance, restricted to the RealEstateManager.
    /// @param amount The amount of tokens to burn, scaled by 10**18 (e.g., 1 RET = 1 * 10**18).
    function burn(uint256 amount) public onlyRealEstateManager nonReentrant {
        _burn(address(this), amount);
    }

    /// @notice Stakes tokens for governance or yield.
    /// @param amount The amount of tokens to stake, scaled by 10**18 (e.g., 1 RET = 1 * 10**18).
    function stake(uint256 amount) public nonReentrant {
        require(balanceOf(msg.sender) >= amount, "Insufficient token balance to stake");
        _transfer(msg.sender, address(this), amount);
        // Add logic for staking benefits
    }

    /// @notice Unstakes tokens.
    /// @param amount The amount of tokens to unstake, scaled by 10**18 (e.g., 1 RET = 1 * 10**18).
    function unstake(uint256 amount) public nonReentrant {
        require(balanceOf(address(this)) >= amount, "Insufficient staked tokens");
        _transfer(address(this), msg.sender, amount);
        // Add logic to handle unstaking conditions or penalties
    }

    /// @notice Pays for a service with tokens.
    /// @param amount The amount of tokens to pay, scaled by 10**18 (e.g., 1 RET = 1 * 10**18).
    /// @param _serviceProvider The address of the service provider.
    function payForService(uint256 amount, address _serviceProvider) public nonReentrant {
        require(balanceOf(msg.sender) >= amount, "Insufficient token balance to pay for service");
        require(_serviceProvider != address(0), "Address cannot be a zero address");
        require(amount > 0, "Amount must be greater than zero");
        _transfer(msg.sender, _serviceProvider, amount);
    }

    /// @notice Distributes yield (e.g., rental income) to fractional owners of a property, restricted to the RentalContract.
    /// @param _propertyId The ID of the property.
    /// @param _totalYieldInTokens The total amount of yield to distribute, scaled by 10**18 (e.g., 1 RET = 1 * 10**18).
    function distributeYield(uint256 _propertyId, uint256 _totalYieldInTokens) public onlyRentalContract nonReentrant {
        uint256 totalTokensForProperty = propertyTotalTokens[_propertyId];
        require(totalTokensForProperty > 0, "No tokens issued for this property");
        require(balanceOf(address(this)) >= _totalYieldInTokens, "Insufficient RET token balance for yield distribution");

        // Track remaining yield to handle rounding errors
        uint256 remainingYield = _totalYieldInTokens;
        uint256 distributedYield = 0;

        // Iterate over all token holders for this property
        address[] memory tokenHolders = propertyTokenHolders[_propertyId];
        for (uint256 i = 0; i < tokenHolders.length; i++) {
            address user = tokenHolders[i];
            uint256 userTokenBalance = propertyTokenBalances[_propertyId][user];
            if (userTokenBalance > 0) {
                // Calculate user's share of the yield
                uint256 userYield = (_totalYieldInTokens * userTokenBalance) / totalTokensForProperty;

                if (userYield > 0) {
                    // Ensure we don't distribute more than remaining yield
                    if (distributedYield + userYield > _totalYieldInTokens) {
                        userYield = _totalYieldInTokens - distributedYield;
                    }

                    // Transfer RET tokens to the user
                    _transfer(address(this), user, userYield);

                    distributedYield += userYield;
                    remainingYield -= userYield;
                }
            }
        }

        // If there's remaining yield due to rounding, transfer it to the owner
        if (remainingYield > 0) {
            _transfer(address(this), owner(), remainingYield);
        }

        emit YieldDistributed(_propertyId, _totalYieldInTokens);
    }

    /// @notice Transfers property ownership, including token balances.
    /// @param _propertyId The ID of the property.
    /// @param _newOwner The address of the new owner.
    function transferPropertyOwnership(uint256 _propertyId, address _newOwner) public nonReentrant {
        require(msg.sender == propertyOwners[_propertyId], "Only the owner can transfer property");
        require(_newOwner != address(0), "New owner cannot be zero address");

        // Prevent transfer if the property is listed for sale in Marketplace
        if (marketplace != address(0)) {
            (, , , bool isAvailable) = Marketplace(marketplace).getPropertyListing(_propertyId);
            require(!isAvailable, "Property is currently listed for sale");
        }

        // Prevent transfer if the property is listed for rent in RentalContract
        if (rentalContract != address(0)) {
            RentalContract rental = RentalContract(rentalContract);
            RentalContract.RentalAgreement memory agreement = rental.rentalAgreements(_propertyId);
            require(!agreement.isActive, "Property is currently listed for rent");
        }

        address oldOwner = propertyOwners[_propertyId];
        uint256 tokenBalance = propertyTokenBalances[_propertyId][oldOwner];

        // Transfer token balance to new owner
        if (tokenBalance > 0) {
            propertyTokenBalances[_propertyId][oldOwner] = 0;
            propertyTokenBalances[_propertyId][_newOwner] += tokenBalance;

            // Update propertyTokenHolders: Remove old owner if their balance is now zero
            if (propertyTokenBalances[_propertyId][oldOwner] == 0) {
                uint256 oldOwnerIndex = propertyTokenHolderIndices[_propertyId][oldOwner];
                address lastHolder = propertyTokenHolders[_propertyId][propertyTokenHolders[_propertyId].length - 1];
                propertyTokenHolders[_propertyId][oldOwnerIndex] = lastHolder;
                propertyTokenHolderIndices[_propertyId][lastHolder] = oldOwnerIndex;
                propertyTokenHolders[_propertyId].pop();
                delete propertyTokenHolderIndices[_propertyId][oldOwner];
            }

            // Update propertyTokenHolders: Add new owner if they are not already a holder
            if (propertyTokenBalances[_propertyId][_newOwner] == tokenBalance) { // Only add if this is their first balance
                propertyTokenHolderIndices[_propertyId][_newOwner] = propertyTokenHolders[_propertyId].length;
                propertyTokenHolders[_propertyId].push(_newOwner);
            }
        }

        // Update property ownership
        propertyOwners[_propertyId] = _newOwner;

        // Update userProperties (with duplicate check)
        removePropertyFromUser(oldOwner, _propertyId);
        if (!isPropertyInUserProperties(_newOwner, _propertyId)) {
            userProperties[_newOwner].push(_propertyId);
        }

        emit PropertyOwnershipTransferred(_propertyId, oldOwner, _newOwner);
    }

    // Helper function to check if a property is already in a user's userProperties
    function isPropertyInUserProperties(address _user, uint256 _propertyId) private view returns (bool) {
        uint256[] storage properties = userProperties[_user];
        for (uint256 i = 0; i < properties.length; i++) {
            if (properties[i] == _propertyId) {
                return true;
            }
        }
        return false;
    }

    function removePropertyFromUser(address _oldOwner, uint256 _propertyId) private {
        uint256[] storage properties = userProperties[_oldOwner];
        for (uint256 i = 0; i < properties.length; i++) {
            if (properties[i] == _propertyId) {
                properties[i] = properties[properties.length - 1];
                properties.pop();
                break;
            }
        }
    }

    // Get properties for a user (for UI display or querying)
    function getPropertiesForUser(address _user) public view returns (uint256[] memory) {
        return userProperties[_user];
    }

    // **token distribution**
    
   // market wallet
   // liquidity market - there is liquidity providers 
   // dev wallet

    // Fallback function to receive ETH
    receive() external payable {}
}

// Interface for Marketplace
interface Marketplace {
    function getPropertyListing(uint _propertyId) external view returns (uint, uint, address, bool);
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