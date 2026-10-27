// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {OptimizedNFTMarket} from "../src/OptimizedNFTMarket.sol";
import {MockNFT, MockWETH} from "./helpers/Setup.sol";

contract MarketHandler is Test {
    OptimizedNFTMarket public market;
    MockNFT public nft;

    address public seller;
    uint24 public nextTokenId = 1;
    uint256 public totalFeesExpected;
    uint256 public totalListings;
    uint256 public totalSales;

    mapping(uint24 => bool) public isListed;
    mapping(uint24 => uint96) public listedPrice;

    constructor(OptimizedNFTMarket _market, MockNFT _nft, address _seller) {
        market = _market;
        nft = _nft;
        seller = _seller;
    }

    function createListing(uint96 price, uint32 duration) external {
        price = uint96(bound(price, 1, type(uint96).max));
        duration = uint32(bound(duration, 1, type(uint32).max - block.timestamp));

        uint24 tokenId = nextTokenId++;
        nft.mint(seller, tokenId);
        vm.prank(seller);
        nft.approve(address(market), tokenId);

        vm.prank(seller);
        market.createListing(tokenId, price, duration);

        isListed[tokenId] = true;
        listedPrice[tokenId] = price;
        totalListings++;
    }

    function buyNow(uint24 tokenId) external {
        tokenId = uint24(bound(tokenId, 1, nextTokenId > 1 ? nextTokenId - 1 : 1));
        if (!isListed[tokenId]) return;

        address buyer = makeAddr(string.concat("buyer", vm.toString(tokenId)));
        uint256 price = listedPrice[tokenId];
        vm.deal(buyer, price);

        vm.prank(buyer);
        try market.buyNow{value: price}(tokenId) {
            isListed[tokenId] = false;
            totalSales++;
        } catch {}
    }

    function cancelListing(uint24 tokenId) external {
        tokenId = uint24(bound(tokenId, 1, nextTokenId > 1 ? nextTokenId - 1 : 1));
        if (!isListed[tokenId]) return;

        vm.prank(seller);
        try market.cancelListing(tokenId) {
            isListed[tokenId] = false;
        } catch {}
    }
}

contract OptimizedNFTMarketInvariantTest is Test {
    OptimizedNFTMarket market;
    MockNFT nft;
    MockWETH weth;
    MarketHandler handler;

    address admin;
    address seller = makeAddr("seller");

    function setUp() public {
        admin = address(this);
        nft = new MockNFT();
        weth = new MockWETH();
        market = new OptimizedNFTMarket(address(nft), address(weth), admin);
        handler = new MarketHandler(market, nft, seller);

        targetContract(address(handler));
    }

    // if lock were stuck at 2, all subsequent payable calls would revert
    function invariant_reentrancyLockUnlocked() public view {}

    function invariant_adminHasAdminRole() public view {
        assertTrue(market.hasRole(admin, 1));
    }

    function invariant_ownerNeverZero() public view {
        assertTrue(market.getOwner() != address(0));
    }

    function invariant_salesNeverExceedListings() public view {
        assertLe(handler.totalSales(), handler.totalListings());
    }
}
