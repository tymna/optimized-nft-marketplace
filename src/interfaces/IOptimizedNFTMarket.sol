// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IOptimizedNFTMarket {
    struct BidOrder {
        address bidder;
        address tokenAddress;
        uint256 tokenId;
        uint256 price;
        uint256 expiration;
    }

    // listing+buy
    function createListing(uint24 tokenId, uint96 price, uint32 duration) external;
    function cancelListing(uint24 tokenId) external;
    function buyNow(uint24 tokenId) external payable;

    // offchain bids
    function acceptBid(BidOrder calldata order, bytes calldata signature) external;

    // batch operations
    function batchList(uint24[] calldata tokenIds, uint96[] calldata prices, uint32 duration) external;
    function batchCancel(uint24[] calldata tokenIds) external;
    function batchBuy(uint24[] calldata tokenIds) external payable;

    // admin
    // function setFeeBasisPoints(uint16 newFee) external;
    // function withdrawFees() external;
    // function setFeeRecipient(address newRecipient) external;
}
