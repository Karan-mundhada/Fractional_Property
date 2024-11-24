// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RealEstateToken is ReentrancyGuard {
    struct Property {
        uint256 id;
        string name;
        string location;
        uint256 totalShares;
        uint256 pricePerShare;
        uint256 availableShares;
        uint256 monthlyRent;
        uint256 rentBalance;
        bool isVerified;
        address owner;
        address paymentToken;
    }

    struct Investor {
        uint256 shares;
        uint256 pendingRent;
    }

    uint256 public propertyCount;
    address public verifier;

    mapping(uint256 => Property) public properties;
    mapping(uint256 => mapping(address => Investor)) public investors;
    mapping(uint256 => address[]) public propertyInvestors;

    // Events
    event PropertyListed(
        uint256 indexed propertyId,
        string name,
        string location,
        uint256 totalShares,
        uint256 pricePerShare,
        uint256 monthlyRent,
        address owner,
        address paymentToken
    );
    event PropertyVerified(uint256 indexed propertyId, bool verified);
    event SharesPurchased(uint256 indexed propertyId, address indexed buyer, uint256 shares);
    event RentPaid(uint256 indexed propertyId, uint256 amount);
    event RentWithdrawn(uint256 indexed propertyId, address indexed investor, uint256 amount);

    constructor() {
        verifier = msg.sender; // Set deployer as verifier
    }

    modifier onlyVerifier() {
        require(msg.sender == verifier, "Only verifier can call this");
        _;
    }

    function setVerifier(address _newVerifier) external onlyVerifier {
        require(_newVerifier != address(0), "Invalid address");
        verifier = _newVerifier;
    }

    function listProperty(
        string memory _name,
        string memory _location,
        uint256 _totalShares,
        uint256 _pricePerShare,
        uint256 _monthlyRent,
        address _paymentToken
    ) external returns (uint256) {
        require(bytes(_name).length > 0, "Name required");
        require(_totalShares > 0 && _pricePerShare > 0, "Invalid shares or price");
        require(_paymentToken != address(0), "Invalid payment token");

        propertyCount++;
        properties[propertyCount] = Property({
            id: propertyCount,
            name: _name,
            location: _location,
            totalShares: _totalShares,
            pricePerShare: _pricePerShare,
            availableShares: _totalShares,
            monthlyRent: _monthlyRent,
            rentBalance: 0,
            isVerified: false,
            owner: msg.sender,
            paymentToken: _paymentToken
        });

        emit PropertyListed(
            propertyCount,
            _name,
            _location,
            _totalShares,
            _pricePerShare,
            _monthlyRent,
            msg.sender,
            _paymentToken
        );

        return propertyCount;
    }

    function verifyProperty(uint256 _propertyId, bool _verified) external onlyVerifier {
        require(_propertyId > 0 && _propertyId <= propertyCount, "Invalid property ID");
        properties[_propertyId].isVerified = _verified;
        emit PropertyVerified(_propertyId, _verified);
    }

    function buyShares(uint256 _propertyId, uint256 _shares) external nonReentrant {
        Property storage property = properties[_propertyId];
        require(property.isVerified, "Property not verified");
        require(_shares > 0 && _shares <= property.availableShares, "Invalid share amount");

        uint256 cost = property.pricePerShare * _shares;
        IERC20 token = IERC20(property.paymentToken);
        require(token.transferFrom(msg.sender, property.owner, cost), "Payment failed");

        property.availableShares -= _shares;

        if (investors[_propertyId][msg.sender].shares == 0) {
            propertyInvestors[_propertyId].push(msg.sender);
        }
        investors[_propertyId][msg.sender].shares += _shares;

        emit SharesPurchased(_propertyId, msg.sender, _shares);
    }

    function payRent(uint256 _propertyId, uint256 _amount) external nonReentrant {
        Property storage property = properties[_propertyId];
        require(property.isVerified, "Property not verified");
        require(_amount > 0, "Invalid rent amount");

        IERC20 token = IERC20(property.paymentToken);
        require(token.transferFrom(msg.sender, address(this), _amount), "Rent payment failed");

        uint256 totalSharesSold = property.totalShares - property.availableShares;
        require(totalSharesSold > 0, "No shares sold");

        uint256 rentPerShare = _amount / totalSharesSold;
        for (uint256 i = 0; i < propertyInvestors[_propertyId].length; i++) {
            address investor = propertyInvestors[_propertyId][i];
            uint256 shares = investors[_propertyId][investor].shares;
            if (shares > 0) {
                investors[_propertyId][investor].pendingRent += rentPerShare * shares;
            }
        }

        emit RentPaid(_propertyId, _amount);
    }

    function withdrawRent(uint256 _propertyId) external nonReentrant {
        uint256 amount = investors[_propertyId][msg.sender].pendingRent;
        require(amount > 0, "No rent to withdraw");

        investors[_propertyId][msg.sender].pendingRent = 0;

        IERC20 token = IERC20(properties[_propertyId].paymentToken);
        require(token.transfer(msg.sender, amount), "Rent withdrawal failed");

        emit RentWithdrawn(_propertyId, msg.sender, amount);
    }

    // View functions
    function getShareholderBalance(uint256 _propertyId, address _investor)
        external
        view
        returns (uint256 shares, uint256 pendingRent)
    {
        Investor memory investor = investors[_propertyId][_investor];
        return (investor.shares, investor.pendingRent);
    }
}
