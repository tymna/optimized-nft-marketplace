// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IOptimizedNFTMarket} from "./interfaces/IOptimizedNFTMarket.sol";
import {Types} from "./libraries/Types.sol";
import {RoleManager} from "./abstract/RoleManager.sol";
import {Errors} from "./libraries/Errors.sol";
import {IERC721} from "./interfaces/IERC721.sol";

// invariant: NFT can be listed/canceled only by current token owner and marketpalce must be approved
contract OptimizedNFTMarket is IOptimizedNFTMarket, RoleManager {
    mapping(uint24 tokenId => Types.Listing) private s_listings;
    mapping(bytes32 orderHash => bool) private s_usedOrders;

    bytes32 public constant TYPEHASH = 0xec47fb701d2e69e338dc5bf05105d9c27e44fc14c1a3688f94e54ce93089eb38; // keccak256("BidOrder(address bidder,address tokenAddress,uint256 tokenId,uint256 price,uint256 expiration)");
    bytes32 public immutable DOMAIN_SEPARATOR;
    address immutable i_nftContract;
    address immutable i_weth;
    uint256 private s_fees;

    uint256 s_feeRate = 50; // 0,5%
    uint256 private s_reentrancyLock = 1; // 1 = unlocked, 2 = locked

    uint8 internal constant STATUS_ACTIVE = 0;
    uint8 internal constant STATUS_FINISHED = 1;
    uint8 internal constant STATUS_CANCELED = 2;
    uint8 internal constant MAX_BATCH = 10;

    modifier onlyTokenOwner(uint24 tokenId) {
        if (IERC721(i_nftContract).ownerOf(tokenId) != msg.sender) {
            _revert(Errors.NotTokenOwner);
        }
        _;
    }

    modifier onlyApprovedToken(uint24 tokenId) {
        if (
            IERC721(i_nftContract).getApproved(tokenId) != address(this)
                && !IERC721(i_nftContract).isApprovedForAll(IERC721(i_nftContract).ownerOf(tokenId), address(this))
        ) {
            _revert(Errors.NotApproved);
        }
        _;
    }

    constructor(address nftContract, address weth, address admin) RoleManager(admin) {
        i_nftContract = nftContract;
        i_weth = weth;
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

    /* ───── Listing ───── */
    function createListing(uint24 tokenId, uint32 price, uint32 duration)
        external
        onlyTokenOwner(tokenId)
        onlyApprovedToken(tokenId)
    {
        bytes32 listingSlot = _getListingSlot(tokenId);

        assembly {
            // 1. block only if listing is ACTIVE and not expired
            let existing := sload(listingSlot)
            if existing {
                let status := and(shr(24, existing), 0xff)
                // FINISHED or CANCELED -> allow overwrite
                if iszero(status) {
                    // status is ACTIVE — check expiry
                    let expiry := and(shr(32, existing), 0xffffffff)
                    if gt(expiry, timestamp()) {
                        mstore(0x00, 0xa3d582ec) // "AlreadyListed()"
                        revert(0x1c, 0x04)
                    }
                }
            }

            // 2. price is > 0
            if iszero(price) {
                mstore(0x00, 0x00bfc921) // "InvalidPrice()"
                revert(0x1c, 0x04)
            }

            // 3. duration is > 0
            if iszero(duration) {
                mstore(0x00, 0x76166401) // "InvalidDuration()"
                revert(0x1c, 0x04)
            }

            // prepare data
            //  [  tokenId  ][ status ][   expiry   ][   price    ][                seller                ]
            //  [  24 bits  ][ 8 bits ][  32 bits   ][  32 bits   ][               160 bits               ]

            let expiry := add(timestamp(), duration)
            let packed := or(shl(96, caller()), or(shl(64, price), or(shl(32, expiry), or(shl(24, 0), tokenId))))
            // update mapping with listing data (packed)
            sstore(listingSlot, packed)

            let ptr := mload(0x40)
            mstore(ptr, price)
            mstore(add(ptr, 0x20), expiry)
            log3(ptr, 0x40, 0x537e00a4f0434e6d8a8e3515113edc354084342a11d999d7f5dba4c85a744364, tokenId, caller()) // ListingCreated(uint24,address,uint32,uint32)
        }
    }

    function cancelListing(uint24 tokenId) external onlyTokenOwner(tokenId) {
        bytes32 listingSlot = _getListingSlot(tokenId);
        assembly {
            let existing := sload(listingSlot)

            if iszero(existing) {
                mstore(0x00, 0x665c1c57) // "NotListed()"
                revert(0x1c, 0x04)
            }

            let status := and(shr(24, existing), 0xff)
            // must be ACTIVE (0) to cancel
            if status {
                mstore(0x00, 0x665c1c57) // "NotListed()" — already FINISHED or CANCELED
                revert(0x1c, 0x04)
            }

            // set status to CANCELED (2), keep rest of packed data
            let cleared := and(existing, not(shl(24, 0xff)))
            sstore(listingSlot, or(cleared, shl(24, 2)))
            log3(0x00, 0x00, 0xa7855ec39fe137e37a21233651cb88e7ce7553e3edb3ab6a9b8b1a68eb63dbb3, tokenId, caller()) // ListingCanceled(uint24,address)
        }
    }

    /* ───── Buy ───── */
    function buyNow(uint24 tokenId) external payable {
        bytes32 listingSlot = _getListingSlot(tokenId);
        address nftContract = i_nftContract;

        assembly {
            // reentrancy lock
            if eq(sload(s_reentrancyLock.slot), 2) {
                mstore(0x00, 0x8beb9d16) // ReentrancyGuard()
                revert(0x1c, 0x04)
            }
            sstore(s_reentrancyLock.slot, 2)

            let existing := sload(listingSlot)

            if iszero(existing) {
                mstore(0x00, 0x665c1c57) // "NotListed()"
                revert(0x1c, 0x04)
            }

            let status := and(shr(24, existing), 0xff)
            if status {
                mstore(0x00, 0x665c1c57) // "NotListed()" — already FINISHED or CANCELED
                revert(0x1c, 0x04)
            }

            let expiry := and(shr(32, existing), 0xffffffff)
            if lt(expiry, timestamp()) {
                mstore(0x00, 0x398cfd02) // "ListingExpired()"
                revert(0x1c, 0x04)
            }

            let price := and(shr(64, existing), 0xffffffff)
            let seller := shr(96, existing)

            if iszero(eq(callvalue(), price)) {
                mstore(0x00, 0xcd1c8867) // "InsufficientPayment()"
                revert(0x1c, 0x04)
            }

            let cleared := and(existing, not(shl(24, 0xff)))
            sstore(listingSlot, or(cleared, shl(24, 1))) // change the status

            // compute fee and store BEFORE external calls (CEI)
            let feeRate := sload(s_feeRate.slot)
            let fee := div(mul(price, feeRate), 10000)
            let sellerPayment := sub(price, fee)
            sstore(s_fees.slot, add(sload(s_fees.slot), fee))

            // 1. transfer nft
            let ptr := mload(0x40)
            mstore(ptr, shl(224, 0x23b872dd)) // selector — shifted to first 4 bytes
            mstore(add(ptr, 0x04), seller)
            mstore(add(ptr, 0x24), caller())
            mstore(add(ptr, 0x44), tokenId)
            mstore(0x40, add(ptr, 0x64))

            if iszero(call(gas(), nftContract, 0, ptr, 0x64, 0x00, 0x00)) {
                mstore(0x00, 0x90b8ec18) // "TransferFailed()"
                revert(0x1c, 0x04)
            }

            // 2. transfer ETH to seller
            if iszero(call(gas(), seller, sellerPayment, 0x00, 0x00, 0x00, 0x00)) {
                mstore(0x00, 0xf499da20) // "PaymentFailed()"
                revert(0x1c, 0x04)
            }

            // emit Sale(uint24 indexed tokenId, address indexed seller, address indexed buyer, uint256 price, uint256 fee)
            mstore(ptr, price)
            mstore(add(ptr, 0x20), fee)
            log4(
                ptr,
                0x40,
                0xbdd2ab87cb3db929b9ccf1186569a97596f8cb3d4ce5fe1bc468e27f10983839,
                tokenId,
                seller,
                caller()
            )

            // unlock
            sstore(s_reentrancyLock.slot, 1)
        }
    }

    /* ───── Bids ───── */
    // Off-Chain Order Book with On-Chain Settlement

    // invariants:
    //   listing must exist, be ACTIVE, and not expired
    //   bid order must not be expired
    //   order must not be replayed
    //   signature must recover to order.bidder
    //   order.tokenAddress == i_nftContract
    //   NFT: seller → bidder, ETH: bidder → seller
    function acceptBid(BidOrder calldata order, bytes calldata signature)
        external
        onlyTokenOwner(uint24(order.tokenId))
    {
        bytes32 domainSeparator = DOMAIN_SEPARATOR;
        address nftContract = i_nftContract;
        address weth = i_weth;

        assembly {
            // reentrancy lock
            if eq(sload(s_reentrancyLock.slot), 2) {
                mstore(0x00, 0x8beb9d16) // ReentrancyGuard()
                revert(0x1c, 0x04)
            }
            sstore(s_reentrancyLock.slot, 2)

            // --- expiration check ---
            if lt(calldataload(add(order, 0x80)), timestamp()) {
                mstore(0x00, 0xcc6d1b44) // BidExpired()
                revert(0x1c, 0x04)
            }

            // --- tokenAddress must match i_nftContract ---
            if iszero(eq(calldataload(add(order, 0x20)), nftContract)) {
                mstore(0x00, 0x28716b92) // TokenAddressMismatch()
                revert(0x1c, 0x04)
            }

            // --- compute listingSlot inline (replaces _getListingSlot call) ---
            mstore(0x00, and(calldataload(add(order, 0x40)), 0xffffff)) // tokenId masked to uint24
            mstore(0x20, s_listings.slot)
            let listingSlot := keccak256(0x00, 0x40)

            // --- listing validation ---
            let existing := sload(listingSlot)

            if iszero(existing) {
                mstore(0x00, 0x665c1c57) // NotListed()
                revert(0x1c, 0x04)
            }
            if and(shr(24, existing), 0xff) {
                mstore(0x00, 0x665c1c57) // NotListed() — already FINISHED or CANCELED
                revert(0x1c, 0x04)
            }
            if lt(and(shr(32, existing), 0xffffffff), timestamp()) {
                mstore(0x00, 0x398cfd02) // ListingExpired()
                revert(0x1c, 0x04)
            }

            // structHash (read directly from calldata)
            let ptr := mload(0x40)
            mstore(ptr, 0xec47fb701d2e69e338dc5bf05105d9c27e44fc14c1a3688f94e54ce93089eb38) // TYPEHASH
            mstore(add(ptr, 0x20), calldataload(order)) // bidder
            mstore(add(ptr, 0x40), calldataload(add(order, 0x20))) // tokenAddress
            mstore(add(ptr, 0x60), calldataload(add(order, 0x40))) // tokenId
            mstore(add(ptr, 0x80), calldataload(add(order, 0x60))) // price
            mstore(add(ptr, 0xA0), calldataload(add(order, 0x80))) // expiration

            // digest → scratch 0x00 (eliminates a stack variable)
            {
                let structHash := keccak256(ptr, 0xC0)
                mstore(ptr, 0x1901)
                mstore(add(ptr, 0x20), domainSeparator)
                mstore(add(ptr, 0x40), structHash)
                mstore(0x00, keccak256(add(ptr, 0x1e), 0x42))
            }

            // --- signature validation & ecrecover ---
            if iszero(eq(signature.length, 65)) {
                mstore(0x00, 0x12345678) // InvalidSignatureLength()
                revert(0x1c, 0x04)
            }

            {
                mstore(ptr, mload(0x00)) // digest from scratch
                mstore(add(ptr, 0x20), byte(0, calldataload(add(signature.offset, 0x40)))) // v
                mstore(add(ptr, 0x40), calldataload(signature.offset)) // r
                mstore(add(ptr, 0x60), calldataload(add(signature.offset, 0x20))) // s
            }

            if iszero(staticcall(gas(), 0x01, ptr, 0x80, ptr, 0x20)) {
                revert(0, 0)
            }

            if iszero(mload(ptr)) {
                mstore(0x00, 0x20c13b0b) // InvalidSignature()
                revert(0x1c, 0x04)
            }

            // verify signer == bidder
            if iszero(eq(mload(ptr), calldataload(order))) {
                mstore(0x00, 0x20c13b0b) // InvalidSignature()
                revert(0x1c, 0x04)
            }

            // replay protection — digest still at 0x00 (revert paths above don't fall through)
            mstore(0x20, 1)
            let orderSlot := keccak256(0x00, 0x40)
            if sload(orderSlot) {
                mstore(0x00, 0x88b39043) // OrderAlreadyUsed()
                revert(0x1c, 0x04)
            }
            sstore(orderSlot, 1)

            let seller := shr(96, existing)

            // update listing status to FINISHED (1)
            sstore(listingSlot, or(and(existing, not(shl(24, 0xff))), shl(24, 1)))

            // --- transfer NFT ---
            mstore(ptr, shl(224, 0x23b872dd)) // selector
            mstore(add(ptr, 0x04), seller) // from
            mstore(add(ptr, 0x24), calldataload(order)) // to (bidder)
            mstore(add(ptr, 0x44), and(calldataload(add(order, 0x40)), 0xffffff)) // tokenId

            if iszero(call(gas(), nftContract, 0, ptr, 0x64, 0x00, 0x00)) {
                mstore(0x00, 0x90b8ec18) // TransferFailed()
                revert(0x1c, 0x04)
            }

            // --- transfer WETH from bidder to seller ---
            mstore(ptr, shl(224, 0x23b872dd)) // transferFrom(address,address,uint256)
            mstore(add(ptr, 0x04), calldataload(order)) // from: bidder
            mstore(add(ptr, 0x24), seller) // to: seller
            mstore(add(ptr, 0x44), calldataload(add(order, 0x60))) // amount: price

            if iszero(call(gas(), weth, 0, ptr, 0x64, 0x00, 0x20)) {
                mstore(0x00, 0xf499da20) // PaymentFailed()
                revert(0x1c, 0x04)
            }
            // check return value (ERC20 transferFrom returns bool)
            if iszero(mload(0x00)) {
                mstore(0x00, 0xf499da20) // PaymentFailed()
                revert(0x1c, 0x04)
            }

            // unlock
            sstore(s_reentrancyLock.slot, 1)
        }
    }

    /* ───── BATCH OPERATIONS ───── */
    // bound max batch size
    function batchList(uint24[] calldata tokenIds, uint32[] calldata prices, uint32 duration) external {
        address nftContract = i_nftContract;

        assembly {
            if iszero(duration) {
                mstore(0x00, 0x76166401) // "InvalidDuration()"
                revert(0x1c, 0x04)
            }

            if or(gt(tokenIds.length, MAX_BATCH), lt(tokenIds.length, 2)) {
                switch gt(tokenIds.length, MAX_BATCH)
                case 1 { mstore(0x00, 0xc06666b8) } // BatchToBig()
                default { mstore(0x00, 0x7103b805) } // BatchTooSmall()
                revert(0x1c, 0x04)
            }

            if iszero(eq(tokenIds.length, prices.length)) {
                mstore(0x00, 0xff633a38) // "LengthMismatch()"
                revert(0x1c, 0x04)
            }

            let len := tokenIds.length

            let expiry := add(timestamp(), duration)

            for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                let tokenId := and(calldataload(add(tokenIds.offset, mul(i, 0x20))), 0xffffff)
                let price := and(calldataload(add(prices.offset, mul(i, 0x20))), 0xffffffff)

                // ── ownerOf(tokenId) → must == caller ──
                mstore(0x00, shl(224, 0x6352211e))
                mstore(0x04, tokenId)
                if iszero(staticcall(gas(), nftContract, 0x00, 0x24, 0x00, 0x20)) {
                    revert(0x00, 0x00)
                }
                if iszero(eq(mload(0x00), caller())) {
                    mstore(0x00, 0x59dc379f) // NotTokenOwner()
                    revert(0x1c, 0x04)
                }

                // ── getApproved(tokenId) || isApprovedForAll(owner, this) ──
                mstore(0x00, shl(224, 0x081812fc)) // getApproved(uint256)
                mstore(0x04, tokenId)
                if iszero(staticcall(gas(), nftContract, 0x00, 0x24, 0x00, 0x20)) {
                    revert(0x00, 0x00)
                }
                if iszero(eq(mload(0x00), address())) {
                    // fallback: isApprovedForAll(owner, marketplace)
                    mstore(0x00, shl(224, 0xe985e9c5)) // isApprovedForAll(address,address)
                    mstore(0x04, caller()) // owner (already verified == caller)
                    mstore(0x24, address()) // operator (this contract)
                    if iszero(staticcall(gas(), nftContract, 0x00, 0x44, 0x00, 0x20)) {
                        revert(0x00, 0x00)
                    }
                    if iszero(mload(0x00)) {
                        mstore(0x00, 0xc19f17a9) // NotApproved()
                        revert(0x1c, 0x04)
                    }
                }

                // ── price > 0 ──
                if iszero(price) {
                    mstore(0x00, 0x00bfc921) // InvalidPrice()
                    revert(0x1c, 0x04)
                }

                // ── listing slot: keccak256(tokenId, s_listings.slot) ──
                mstore(0x00, tokenId)
                mstore(0x20, s_listings.slot)
                let listingSlot := keccak256(0x00, 0x40)

                // ── block if ACTIVE and not expired ──
                let existing := sload(listingSlot)
                if existing {
                    let status := and(shr(24, existing), 0xff)
                    if iszero(status) {
                        let existingExpiry := and(shr(32, existing), 0xffffffff)
                        if gt(existingExpiry, timestamp()) {
                            mstore(0x00, 0xa3d582ec) // AlreadyListed()
                            revert(0x1c, 0x04)
                        }
                    }
                }

                // ── pack and store ──
                //  [  tokenId  ][ status ][   expiry   ][   price    ][                seller                ]
                //  [  24 bits  ][ 8 bits ][  32 bits   ][  32 bits   ][               160 bits               ]
                let packed := or(shl(96, caller()), or(shl(64, price), or(shl(32, expiry), tokenId)))
                sstore(listingSlot, packed)

                // ── emit ListingCreated(uint24 indexed tokenId, address indexed seller, uint32 price, uint32 expiry) ──
                let ptr := mload(0x40)
                mstore(ptr, price)
                mstore(add(ptr, 0x20), expiry)
                log3(ptr, 0x40, 0x537e00a4f0434e6d8a8e3515113edc354084342a11d999d7f5dba4c85a744364, tokenId, caller())
            }
        }
    }

    function batchCancel(uint24[] calldata tokenIds) external {
        address nftContract = i_nftContract;

        assembly {
            if or(gt(tokenIds.length, MAX_BATCH), lt(tokenIds.length, 2)) {
                switch gt(tokenIds.length, MAX_BATCH)
                case 1 { mstore(0x00, 0xc06666b8) } // BatchToBig()
                default { mstore(0x00, 0x7103b805) } // BatchTooSmall()
                revert(0x1c, 0x04)
            }

            let len := tokenIds.length

            for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                let tokenId := and(calldataload(add(tokenIds.offset, mul(i, 0x20))), 0xffffff)

                // ── ownerOf(tokenId) → must == caller ──
                mstore(0x00, shl(224, 0x6352211e))
                mstore(0x04, tokenId)
                if iszero(staticcall(gas(), nftContract, 0x00, 0x24, 0x00, 0x20)) {
                    revert(0x00, 0x00)
                }
                if iszero(eq(mload(0x00), caller())) {
                    mstore(0x00, 0x59dc379f) // NotTokenOwner()
                    revert(0x1c, 0x04)
                }

                // ── listing slot: keccak256(tokenId, s_listings.slot) ──
                mstore(0x00, tokenId)
                mstore(0x20, s_listings.slot)
                let listingSlot := keccak256(0x00, 0x40)

                // ── validate: must exist and be ACTIVE ──
                let existing := sload(listingSlot)

                if iszero(existing) {
                    mstore(0x00, 0x665c1c57) // NotListed()
                    revert(0x1c, 0x04)
                }

                let status := and(shr(24, existing), 0xff)
                if status {
                    mstore(0x00, 0x665c1c57) // NotListed() — already FINISHED or CANCELED
                    revert(0x1c, 0x04)
                }

                // ── set status to CANCELED (2), keep rest ──
                let cleared := and(existing, not(shl(24, 0xff)))
                sstore(listingSlot, or(cleared, shl(24, 2)))

                // ── emit ListingCanceled(uint24 indexed tokenId, address indexed seller) ──
                log3(0x00, 0x00, 0xa7855ec39fe137e37a21233651cb88e7ce7553e3edb3ab6a9b8b1a68eb63dbb3, tokenId, caller())
            }
        }
    }

    function batchBuy(uint24[] calldata tokenIds) external payable {
        address nftContract = i_nftContract;

        assembly {
            // reentrancy lock
            if eq(sload(s_reentrancyLock.slot), 2) {
                mstore(0x00, 0x8beb9d16) // ReentrancyGuard()
                revert(0x1c, 0x04)
            }
            sstore(s_reentrancyLock.slot, 2)

            if or(gt(tokenIds.length, MAX_BATCH), lt(tokenIds.length, 2)) {
                switch gt(tokenIds.length, MAX_BATCH)
                case 1 { mstore(0x00, 0xc06666b8) } // BatchToBig()
                default { mstore(0x00, 0x7103b805) } // BatchTooSmall()
                revert(0x1c, 0x04)
            }

            let len := tokenIds.length
            let ptr := mload(0x40)
            let totalSpent := 0

            for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                let tokenId := and(calldataload(add(tokenIds.offset, mul(i, 0x20))), 0xffffff)

                // ── validate + extract + sstore in scoped block ──
                // keeps existing/listingSlot off stack during external calls
                let price := 0
                let seller := 0
                {
                    mstore(0x00, tokenId)
                    mstore(0x20, s_listings.slot)
                    let listingSlot := keccak256(0x00, 0x40)
                    let existing := sload(listingSlot)

                    if iszero(existing) {
                        mstore(0x00, 0x665c1c57) // NotListed()
                        revert(0x1c, 0x04)
                    }
                    // status != ACTIVE
                    if and(shr(24, existing), 0xff) {
                        mstore(0x00, 0x665c1c57) // NotListed() — FINISHED or CANCELED
                        revert(0x1c, 0x04)
                    }
                    // expired
                    if lt(and(shr(32, existing), 0xffffffff), timestamp()) {
                        mstore(0x00, 0x398cfd02) // ListingExpired()
                        revert(0x1c, 0x04)
                    }

                    price := and(shr(64, existing), 0xffffffff)
                    seller := shr(96, existing)
                    totalSpent := add(totalSpent, price)

                    // set status to FINISHED (1) before external calls (CEI)
                    sstore(listingSlot, or(and(existing, not(shl(24, 0xff))), shl(24, 1)))
                }

                // compute fee and store BEFORE external calls (CEI)
                let feeRate := sload(s_feeRate.slot)
                let fee := div(mul(price, feeRate), 10000)
                let sellerPayment := sub(price, fee)
                sstore(s_fees.slot, add(sload(s_fees.slot), fee))

                // ── transferFrom(seller, caller, tokenId) ──
                mstore(ptr, shl(224, 0x23b872dd))
                mstore(add(ptr, 0x04), seller)
                mstore(add(ptr, 0x24), caller())
                mstore(add(ptr, 0x44), tokenId)

                if iszero(call(gas(), nftContract, 0, ptr, 0x64, 0x00, 0x00)) {
                    mstore(0x00, 0x90b8ec18) // TransferFailed()
                    revert(0x1c, 0x04)
                }

                // ── send sellerPayment ETH to seller ──
                if iszero(call(gas(), seller, sellerPayment, 0x00, 0x00, 0x00, 0x00)) {
                    mstore(0x00, 0xf499da20) // PaymentFailed()
                    revert(0x1c, 0x04)
                }

                // ── emit Sale(uint24 indexed tokenId, address indexed seller, address indexed buyer, uint256 price, uint256 fee) ──
                mstore(ptr, price)
                mstore(add(ptr, 0x20), fee)
                log4(
                    ptr,
                    0x40,
                    0xbdd2ab87cb3db929b9ccf1186569a97596f8cb3d4ce5fe1bc468e27f10983839,
                    tokenId,
                    seller,
                    caller()
                )
            }

            // exact payment check — reverts entire tx if mismatch
            if iszero(eq(callvalue(), totalSpent)) {
                mstore(0x00, 0x3c6b4b28) // InvalidPayment()
                revert(0x1c, 0x04)
            }

            // unlock
            sstore(s_reentrancyLock.slot, 1)
        }
    }

    function setFeeRate(uint256 feeRate) external onlyOwner {
        assembly {
            // cap at 10000 bps (100%) — prevents sub(price, fee) wrap in buyNow/batchBuy
            if gt(feeRate, 10000) {
                mstore(0x00, 0xcd4e6167) // FeeTooHigh()
                revert(0x1c, 0x04)
            }

            let currentRate := sload(s_feeRate.slot)

            sstore(s_feeRate.slot, feeRate)

            // emit FeeRateChanged(address indexed owner, uint256 oldRate, uint256 newRate)
            let owner := sload(0)
            mstore(0x00, currentRate)
            mstore(0x20, feeRate)
            log2(0x00, 0x40, 0x8df11a6eae48bfda477a5ab0706682b383a916f1d550dd5f6d5857dd4f839793, owner)
        }
    }

    function withdrawFees() external onlyOwner {
        assembly {
            // reentrancy lock
            if eq(sload(s_reentrancyLock.slot), 2) {
                mstore(0x00, 0x8beb9d16) // ReentrancyGuard()
                revert(0x1c, 0x04)
            }
            sstore(s_reentrancyLock.slot, 2)

            let fees := sload(s_fees.slot)

            if iszero(fees) {
                mstore(0x00, 0x2002b183) // NotFeesCollected()
                revert(0x1c, 0x04)
            }

            sstore(s_fees.slot, 0)

            // get owner
            let owner := sload(0)
            if iszero(call(gas(), owner, fees, 0, 0, 0, 0)) {
                mstore(0x00, 0xf499da20) // PaymentFailed()
                revert(0x1c, 0x04)
            }

            // emit FeesWithdrawn(address indexed owner, uint256 amount)
            mstore(0x00, fees)
            log2(0x00, 0x20, 0xc0819c13be868895eb93e40eaceb96de976442fa1d404e5c55f14bb65a8c489a, owner)

            // unlock
            sstore(s_reentrancyLock.slot, 1)
        }
    }

    /* ───── INTERNAL ───── */
    function _getListingSlot(uint256 key) internal pure returns (bytes32 slot) {
        assembly {
            mstore(0x00, key)
            mstore(0x20, s_listings.slot)
            slot := keccak256(0x00, 0x40)
        }
    }
}
