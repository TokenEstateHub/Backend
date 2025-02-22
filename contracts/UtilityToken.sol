// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract UtilityToken is ERC20, Ownable, ReentrancyGuard { 

    address public admin; 
    address public manager; 
    address public realEstateManager;
    address public marketplace;
    address public rentalContract;

    uint256 public constant INITIAL_SUPPLY = 10000000;
  
    uint256 public constant TOKENS_PER_ETH = 10000; // 1 ETH = 10,000 RET tokens
    uint256 public constant WEI_PER_TOKEN = 1e14; // 10**14 wei per RET token (1 ETH / 10,000)

    mapping(uint256 => uint256) public propertyTotalTokens;
    mapping(address => uint256[]) public userProperties;
    mapping(uint256 => address) public propertyOwners;
    mapping(uint256 => mapping(address => uint256)) public propertyTokenBalances;
    mapping(uint256 => address[]) public propertyTokenHolders;
    mapping(uint256 => mapping(address => uint256)) public propertyTokenHolderIndices;

    event TokensMintedForProperty(uint indexed propertyId, address indexed to, uint amount);
    event YieldDistributed(uint indexed propertyId, uint amount);
    event PropertyOwnershipTransferred(uint indexed propertyId, address indexed oldOwner, address indexed newOwner);
    event RealEstateManagerSet(address indexed realEstateManager);

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
        require(msg.sender == admin, "Only the Admin can perform this action");
        _;
    }

    modifier onlyRentalContract() {
        require(msg.sender == rentalContract, "Only the RentalContract can perform this action");
        _;
    }

    constructor() ERC20("RealEstateToken", "RET") Ownable(msg.sender) {
        manager = msg.sender; 
        admin = msg.sender;
        _mint(msg.sender, INITIAL_SUPPLY); // Mint all 10 million tokens to deployer
    }

    function setRealEstateManager(address _realEstateManager) public onlyOwner {
        require(realEstateManager == address(0), "RealEstateManager address already set");
        require(_realEstateManager != address(0), "RealEstateManager address cannot be zero");
        realEstateManager = _realEstateManager; 
        
        emit RealEstateManagerSet(_realEstateManager);
    }

    function setMarketplace(address _marketplace) public onlyOwner {
        require(_marketplace != address(0), "Marketplace address cannot be zero");
        require(marketplace == address(0), "Marketplace address already set");
        marketplace = _marketplace;
    }

    function setRentalContract(address _rentalContract) public onlyOwner {
        require(_rentalContract != address(0), "RentalContract address cannot be zero");
        require(rentalContract == address(0), "RentalContract address already set");
        rentalContract = _rentalContract;
    }

    function calculatePrice(uint256 _amount) public pure returns (uint256) {
        return _amount * WEI_PER_TOKEN; // Price in wei
    }

    /// @notice Buys tokens by transferring them from the deployer at a fixed rate of 1 ETH = 10,000 RET.
    /// @param _amount The amount of tokens to buy, scaled by 10**18.
    function buy(uint256 _amount) external payable nonReentrant {
        require(_amount > 0, "Amount must be greater than zero");
        uint256 totalCost = calculatePrice(_amount);
        require(msg.value == totalCost, "Send exact ETH amount");
        require(balanceOf(owner()) >= _amount, "Deployer has insufficient tokens");

        _transfer(owner(), msg.sender, _amount); // Transfer from deployer to buyer
    }

    /// @notice Transfers tokens from deployer to a recipient for a property, restricted to RealEstateManager.
    /// @param _propertyId The ID of the property.
    /// @param _to The address to receive the tokens.
    /// @param _amount The amount of tokens to transfer, scaled by 10**18.
    function mintForProperty(uint256 _propertyId, address _to, uint256 _amount) public onlyRealEstateManager {
        require(_to != address(0), "Invalid recipient address");
        require(_amount > 0, "Token amount must be greater than zero");
        require(balanceOf(owner()) >= _amount, "Deployer has insufficient tokens");

        propertyTotalTokens[_propertyId] += _amount;
        if (propertyTokenBalances[_propertyId][_to] == 0) {
            propertyTokenHolderIndices[_propertyId][_to] = propertyTokenHolders[_propertyId].length;
            propertyTokenHolders[_propertyId].push(_to);
        }
        propertyTokenBalances[_propertyId][_to] += _amount;
        if (!isPropertyInUserProperties(_to, _propertyId)) {
            userProperties[_to].push(_propertyId);
        }
        propertyOwners[_propertyId] = _to;
        _transfer(owner(), _to, _amount); // Transfer from deployer to recipient
        
        emit TokensMintedForProperty(_propertyId, _to, _amount);
    }

    function sell(uint256 _amount) external nonReentrant {
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");
        require(_amount > 0, "Amount must be greater than zero");

        uint256 totalRefund = calculatePrice(_amount);
        require(address(this).balance >= totalRefund, "Insufficient contract balance for redemption");

        _burn(msg.sender, _amount);
        (bool success, ) = payable(msg.sender).call{value: totalRefund}("");
        require(success, "Refund failed");
    }

    function burn(uint256 amount) public onlyRealEstateManager nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        _burn(address(this), amount);
    }

    function stake(uint256 amount) public nonReentrant {
        require(balanceOf(msg.sender) >= amount, "Insufficient token balance to stake");
        require(amount > 0, "Amount must be greater than zero");
        _transfer(msg.sender, address(this), amount);
    }

    function unstake(uint256 amount) public nonReentrant {
        require(balanceOf(address(this)) >= amount, "Insufficient staked tokens");
        require(amount > 0, "Amount must be greater than zero");
        _transfer(address(this), msg.sender, amount);
    }

    function payForService(uint256 amount, address _serviceProvider) public nonReentrant {
        require(balanceOf(msg.sender) >= amount, "Insufficient token balance to pay for service");
        require(_serviceProvider != address(0), "Address cannot be a zero address");
        require(amount > 0, "Amount must be greater than zero");
        _transfer(msg.sender, _serviceProvider, amount);
    }

    function distributeYield(uint256 _propertyId, uint256 _totalYieldInTokens) public onlyRentalContract nonReentrant {
        uint256 totalTokensForProperty = propertyTotalTokens[_propertyId];
        require(totalTokensForProperty > 0, "No tokens issued for this property");
        require(_totalYieldInTokens > 0, "Yield amount must be greater than zero");
        require(balanceOf(address(this)) >= _totalYieldInTokens, "Insufficient RET token balance for yield distribution");

        uint256 remainingYield = _totalYieldInTokens;
        uint256 distributedYield = 0;

        address[] memory tokenHolders = propertyTokenHolders[_propertyId];
        for (uint256 i = 0; i < tokenHolders.length; i++) {
            address user = tokenHolders[i];
            uint256 userTokenBalance = propertyTokenBalances[_propertyId][user];
            if (userTokenBalance > 0) {
                uint256 userYield = (_totalYieldInTokens * userTokenBalance) / totalTokensForProperty;

                if (userYield > 0) {
                    if (distributedYield + userYield > _totalYieldInTokens) {
                        userYield = _totalYieldInTokens - distributedYield;
                    }

                    _transfer(address(this), user, userYield);

                    distributedYield += userYield;
                    remainingYield -= userYield;
                }
            }
        }

        if (remainingYield > 0) {
            _transfer(address(this), owner(), remainingYield);
        }

        emit YieldDistributed(_propertyId, _totalYieldInTokens);
    }

    function transferPropertyOwnership(uint256 _propertyId, address _newOwner) public nonReentrant {
        require(msg.sender == propertyOwners[_propertyId], "Only the owner can transfer property");
        require(_newOwner != address(0), "New owner cannot be zero address");

        if (marketplace != address(0)) {
            (, , , bool isAvailable) = Marketplace(marketplace).getPropertyListing(_propertyId);
            require(!isAvailable, "Property is currently listed for sale");
        }

        if (rentalContract != address(0)) {
            RentalContract rental = RentalContract(rentalContract);
            RentalContract.RentalAgreement memory agreement = rental.rentalAgreements(_propertyId);
            require(!agreement.isActive, "Property is currently listed for rent");
        }

        address oldOwner = propertyOwners[_propertyId];
        uint256 tokenBalance = propertyTokenBalances[_propertyId][oldOwner];

        if (tokenBalance > 0) {
            propertyTokenBalances[_propertyId][oldOwner] = 0;
            propertyTokenBalances[_propertyId][_newOwner] += tokenBalance;

            if (propertyTokenBalances[_propertyId][oldOwner] == 0) {
                uint256 oldOwnerIndex = propertyTokenHolderIndices[_propertyId][oldOwner];
                address lastHolder = propertyTokenHolders[_propertyId][propertyTokenHolders[_propertyId].length - 1];
                propertyTokenHolders[_propertyId][oldOwnerIndex] = lastHolder;
                propertyTokenHolderIndices[_propertyId][lastHolder] = oldOwnerIndex;
                propertyTokenHolders[_propertyId].pop();
                delete propertyTokenHolderIndices[_propertyId][oldOwner];
            }

            if (propertyTokenBalances[_propertyId][_newOwner] == tokenBalance) {
                propertyTokenHolderIndices[_propertyId][_newOwner] = propertyTokenHolders[_propertyId].length;
                propertyTokenHolders[_propertyId].push(_newOwner);
            }
        }

        propertyOwners[_propertyId] = _newOwner;

        removePropertyFromUser(oldOwner, _propertyId);
        if (!isPropertyInUserProperties(_newOwner, _propertyId)) {
            userProperties[_newOwner].push(_propertyId);
        }

        emit PropertyOwnershipTransferred(_propertyId, oldOwner, _newOwner);
    }

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

    function getPropertiesForUser(address _user) public view returns (uint256[] memory) {
        return userProperties[_user];
    }

    receive() external payable {}
}

interface Marketplace {
    function getPropertyListing(uint _propertyId) external view returns (uint, uint, address, bool);
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