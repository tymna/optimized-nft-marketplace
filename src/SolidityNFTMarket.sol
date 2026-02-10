// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC721} from "./interfaces/IERC721.sol";

// pure solidity reference — no inline assembly
// mirrors OptimizedNFTMarket for fair gas comparison
contract SolidityNFTMarket {
    struct Listing {
        address seller;
        uint32 price;
        uint32 expiry;
        uint8 status;
        uint24 tokenId;
    }

    struct BidOrder {
        address bidder;
        address tokenAddress;
        uint256 tokenId;
        uint256 price;
        uint256 expiration;
    }

    // errors
    error NotAnOwner();
    error AlreadyOwner();
    error ZeroAddress();
    error NotTokenOwner();
    error NotApproved();
    error AlreadyListed();
    error InvalidPrice();
    error InvalidDuration();
    error NotListed();
    error ListingExpired();
    error InsufficientPayment();
    error TransferFailed();
    error PaymentFailed();
    error ReentrancyGuard();
    error FeeTooHigh();
    error NotFeesCollected();
    error BatchTooBig();
    error BatchTooSmall();
    error LengthMismatch();
    error BidExpired();
    error TokenAddressMismatch();
    error InvalidSignatureLength();
    error InvalidSignature();
    error OrderAlreadyUsed();
    error InvalidRole();
    error CannotRevokeAdmin();
    error HasNoRole();

    // events
    event ListingCreated(uint24 indexed tokenId, address indexed seller, uint32 price, uint32 expiry);
    event ListingCanceled(uint24 indexed tokenId, address indexed seller);
    event Sale(uint24 indexed tokenId, address indexed seller, address indexed buyer, uint256 price, uint256 fee);
    event FeeRateChanged(address indexed owner, uint256 oldRate, uint256 newRate);
    event FeesWithdrawn(address indexed owner, uint256 amount);
    event RoleGranted(address indexed user, uint256 indexed role);
    event RoleRevoked(address indexed user, uint256 indexed role);

    // storage
    mapping(uint24 => Listing) private s_listings;
    mapping(bytes32 => bool) private s_usedOrders;
    mapping(address => uint256) private s_userRole;

    bytes32 public constant TYPEHASH = 0xec47fb701d2e69e338dc5bf05105d9c27e44fc14c1a3688f94e54ce93089eb38;
    bytes32 public immutable DOMAIN_SEPARATOR;
    address immutable i_nftContract;
    address immutable i_weth;

    address private s_owner;
    uint256 private s_fees;
    uint256 public s_feeRate = 50;
    uint256 private s_reentrancyLock = 1;

    uint8 internal constant STATUS_ACTIVE = 0;
    uint8 internal constant STATUS_FINISHED = 1;
    uint8 internal constant STATUS_CANCELED = 2;
    uint8 internal constant MAX_BATCH = 10;

    uint256 private constant ADMIN_ROLE = 1;
    uint256 private constant CREATOR_ROLE = 2;
    uint256 private constant VERIFIED_ROLE = 4;

    modifier onlyOwner() {
        if (msg.sender != s_owner) revert NotAnOwner();
        _;
    }

    modifier onlyTokenOwner(uint24 tokenId) {
        if (IERC721(i_nftContract).ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        _;
    }

    modifier onlyApprovedToken(uint24 tokenId) {
        if (
            IERC721(i_nftContract).getApproved(tokenId) != address(this)
                && !IERC721(i_nftContract).isApprovedForAll(IERC721(i_nftContract).ownerOf(tokenId), address(this))
        ) revert NotApproved();
        _;
    }

    modifier nonReentrant() {
        if (s_reentrancyLock == 2) revert ReentrancyGuard();
        s_reentrancyLock = 2;
        _;
        s_reentrancyLock = 1;
    }

    constructor(address nftContract, address weth, address admin) {
        if (admin == address(0)) revert ZeroAddress();
        i_nftContract = nftContract;
        i_weth = weth;
        s_owner = admin;
        s_userRole[admin] = ADMIN_ROLE;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("OptimizedNFTMarket")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    // --- listing ---

    function createListing(uint24 tokenId, uint32 price, uint32 duration)
        external
        onlyTokenOwner(tokenId)
        onlyApprovedToken(tokenId)
    {
        Listing storage listing = s_listings[tokenId];

        if (listing.seller != address(0)) {
            if (listing.status == STATUS_ACTIVE && listing.expiry > uint32(block.timestamp)) {
                revert AlreadyListed();
            }
        }

        if (price == 0) revert InvalidPrice();
        if (duration == 0) revert InvalidDuration();

        uint32 expiry = uint32(block.timestamp) + duration;

        listing.seller = msg.sender;
        listing.price = price;
        listing.expiry = expiry;
        listing.status = STATUS_ACTIVE;
        listing.tokenId = tokenId;

        emit ListingCreated(tokenId, msg.sender, price, expiry);
    }

    function cancelListing(uint24 tokenId) external onlyTokenOwner(tokenId) {
        Listing storage listing = s_listings[tokenId];

        if (listing.seller == address(0)) revert NotListed();
        if (listing.status != STATUS_ACTIVE) revert NotListed();

        listing.status = STATUS_CANCELED;

        emit ListingCanceled(tokenId, msg.sender);
    }

    // --- buy ---

    function buyNow(uint24 tokenId) external payable nonReentrant {
        Listing storage listing = s_listings[tokenId];

        if (listing.seller == address(0)) revert NotListed();
        if (listing.status != STATUS_ACTIVE) revert NotListed();
        if (listing.expiry < uint32(block.timestamp)) revert ListingExpired();
        if (msg.value != listing.price) revert InsufficientPayment();

        address seller = listing.seller;
        uint256 price = listing.price;

        listing.status = STATUS_FINISHED;

        uint256 fee = (price * s_feeRate) / 10000;
        uint256 sellerPayment = price - fee;
        s_fees += fee;

        IERC721(i_nftContract).transferFrom(seller, msg.sender, tokenId);

        (bool success,) = seller.call{value: sellerPayment}("");
        if (!success) revert PaymentFailed();

        emit Sale(tokenId, seller, msg.sender, price, fee);
    }

    // --- bids ---

    function acceptBid(BidOrder calldata order, bytes calldata signature)
        external
        onlyTokenOwner(uint24(order.tokenId))
        nonReentrant
    {
        if (order.expiration < block.timestamp) revert BidExpired();
        if (order.tokenAddress != i_nftContract) revert TokenAddressMismatch();

        uint24 tokenId = uint24(order.tokenId);
        Listing storage listing = s_listings[tokenId];

        if (listing.seller == address(0)) revert NotListed();
        if (listing.status != STATUS_ACTIVE) revert NotListed();
        if (listing.expiry < uint32(block.timestamp)) revert ListingExpired();

        {
            bytes32 structHash = keccak256(
                abi.encode(TYPEHASH, order.bidder, order.tokenAddress, order.tokenId, order.price, order.expiration)
            );
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

            if (signature.length != 65) revert InvalidSignatureLength();

            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly {
                r := calldataload(signature.offset)
                s := calldataload(add(signature.offset, 0x20))
                v := byte(0, calldataload(add(signature.offset, 0x40)))
            }

            address signer = ecrecover(digest, v, r, s);
            if (signer == address(0)) revert InvalidSignature();
            if (signer != order.bidder) revert InvalidSignature();

            if (s_usedOrders[digest]) revert OrderAlreadyUsed();
            s_usedOrders[digest] = true;
        }

        address seller = listing.seller;
        listing.status = STATUS_FINISHED;

        IERC721(i_nftContract).transferFrom(seller, order.bidder, tokenId);

        _transferWeth(order.bidder, seller, order.price);
    }

    // --- batch ---

    function batchList(uint24[] calldata tokenIds, uint32[] calldata prices, uint32 duration) external {
        if (duration == 0) revert InvalidDuration();
        if (tokenIds.length > MAX_BATCH) revert BatchTooBig();
        if (tokenIds.length < 2) revert BatchTooSmall();
        if (tokenIds.length != prices.length) revert LengthMismatch();

        uint32 expiry = uint32(block.timestamp) + duration;

        for (uint256 i; i < tokenIds.length; ++i) {
            uint24 tokenId = tokenIds[i];
            uint32 price = prices[i];

            if (IERC721(i_nftContract).ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
            if (
                IERC721(i_nftContract).getApproved(tokenId) != address(this)
                    && !IERC721(i_nftContract).isApprovedForAll(msg.sender, address(this))
            ) revert NotApproved();
            if (price == 0) revert InvalidPrice();

            Listing storage listing = s_listings[tokenId];

            if (listing.seller != address(0)) {
                if (listing.status == STATUS_ACTIVE && listing.expiry > uint32(block.timestamp)) {
                    revert AlreadyListed();
                }
            }

            listing.seller = msg.sender;
            listing.price = price;
            listing.expiry = expiry;
            listing.status = STATUS_ACTIVE;
            listing.tokenId = tokenId;

            emit ListingCreated(tokenId, msg.sender, price, expiry);
        }
    }

    function batchCancel(uint24[] calldata tokenIds) external {
        if (tokenIds.length > MAX_BATCH) revert BatchTooBig();
        if (tokenIds.length < 2) revert BatchTooSmall();

        for (uint256 i; i < tokenIds.length; ++i) {
            uint24 tokenId = tokenIds[i];

            if (IERC721(i_nftContract).ownerOf(tokenId) != msg.sender) revert NotTokenOwner();

            Listing storage listing = s_listings[tokenId];

            if (listing.seller == address(0)) revert NotListed();
            if (listing.status != STATUS_ACTIVE) revert NotListed();

            listing.status = STATUS_CANCELED;

            emit ListingCanceled(tokenId, msg.sender);
        }
    }

    function batchBuy(uint24[] calldata tokenIds) external payable nonReentrant {
        if (tokenIds.length > MAX_BATCH) revert BatchTooBig();
        if (tokenIds.length < 2) revert BatchTooSmall();

        uint256 totalSpent;

        for (uint256 i; i < tokenIds.length; ++i) {
            uint24 tokenId = tokenIds[i];
            Listing storage listing = s_listings[tokenId];

            if (listing.seller == address(0)) revert NotListed();
            if (listing.status != STATUS_ACTIVE) revert NotListed();
            if (listing.expiry < uint32(block.timestamp)) revert ListingExpired();

            address seller = listing.seller;
            uint256 price = listing.price;
            totalSpent += price;

            listing.status = STATUS_FINISHED;

            uint256 fee = (price * s_feeRate) / 10000;
            uint256 sellerPayment = price - fee;
            s_fees += fee;

            IERC721(i_nftContract).transferFrom(seller, msg.sender, tokenId);

            (bool success,) = seller.call{value: sellerPayment}("");
            if (!success) revert PaymentFailed();

            emit Sale(tokenId, seller, msg.sender, price, fee);
        }

        if (msg.value != totalSpent) revert InsufficientPayment();
    }

    // --- admin ---

    function setFeeRate(uint256 feeRate) external onlyOwner {
        if (feeRate > 10000) revert FeeTooHigh();
        uint256 oldRate = s_feeRate;
        s_feeRate = feeRate;
        emit FeeRateChanged(s_owner, oldRate, feeRate);
    }

    function withdrawFees() external onlyOwner nonReentrant {
        uint256 fees = s_fees;
        if (fees == 0) revert NotFeesCollected();
        s_fees = 0;

        (bool success,) = s_owner.call{value: fees}("");
        if (!success) revert PaymentFailed();

        emit FeesWithdrawn(s_owner, fees);
    }

    // --- roles ---

    function grantRole(address to, uint256 role) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (role != ADMIN_ROLE && role != CREATOR_ROLE && role != VERIFIED_ROLE) revert InvalidRole();
        s_userRole[to] |= role;
        emit RoleGranted(to, role);
    }

    function revokeRole(address user, uint256 role) external onlyOwner {
        if (user == address(0)) revert ZeroAddress();
        if (role != ADMIN_ROLE && role != CREATOR_ROLE && role != VERIFIED_ROLE) revert InvalidRole();
        if (role == ADMIN_ROLE) revert CannotRevokeAdmin();
        if (s_userRole[user] & role == 0) revert HasNoRole();
        s_userRole[user] &= ~role;
        emit RoleRevoked(user, role);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        if (newOwner == s_owner) revert AlreadyOwner();
        address oldOwner = s_owner;
        s_userRole[oldOwner] = 0;
        s_owner = newOwner;
        s_userRole[newOwner] = ADMIN_ROLE;
    }

    function _transferWeth(address from, address to, uint256 amount) internal {
        (bool success, bytes memory returnData) =
            i_weth.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount));
        if (!success || (returnData.length > 0 && !abi.decode(returnData, (bool)))) revert PaymentFailed();
    }

    // --- getters ---

    function getOwner() external view returns (address) {
        return s_owner;
    }

    function getRoleOfUser(address user) external view returns (uint256) {
        return s_userRole[user];
    }

    function hasRole(address user, uint256 role) external view returns (bool) {
        return (s_userRole[user] & role) > 0;
    }
}
