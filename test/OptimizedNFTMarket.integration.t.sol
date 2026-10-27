// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MarketSetup} from "./helpers/Setup.sol";
import {IOptimizedNFTMarket} from "../src/interfaces/IOptimizedNFTMarket.sol";

contract OptimizedNFTMarketIntegrationTest is MarketSetup {
    // --- list → buy → withdraw fees ---

    function test_flow_listBuyWithdraw() public {
        vm.prank(user);
        market.createListing(1, 1000, 3600);

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000);
        vm.prank(buyer);
        market.buyNow{value: 1000}(1);

        assertEq(nft.ownerOf(1), buyer);

        // 0.5% of 1000 = 5
        uint256 adminBalBefore = admin.balance;
        market.withdrawFees();
        assertEq(admin.balance - adminBalBefore, 5);
    }

    // --- list → acceptBid → weth transfers ---

    function test_flow_listAcceptBid() public {
        vm.prank(user);
        market.createListing(1, 100, 3600);

        uint256 sellerWethBefore = weth.balanceOf(user);
        uint256 bidderWethBefore = weth.balanceOf(bidder);

        IOptimizedNFTMarket.BidOrder memory order = IOptimizedNFTMarket.BidOrder({
            bidder: bidder, tokenAddress: address(nft), tokenId: 1, price: 150, expiration: block.timestamp + 1 hours
        });
        bytes memory sig = _signOrder(order);

        vm.prank(user);
        market.acceptBid(order, sig);

        assertEq(nft.ownerOf(1), bidder);
        assertEq(weth.balanceOf(user), sellerWethBefore + 150);
        assertEq(weth.balanceOf(bidder), bidderWethBefore - 150);
    }

    // --- replay protection ---

    function test_flow_acceptBid_RevertsOnReplay() public {
        _mintAndApprove(user, 2);

        vm.startPrank(user);
        market.createListing(1, 100, 3600);
        market.createListing(2, 100, 3600);
        vm.stopPrank();

        IOptimizedNFTMarket.BidOrder memory order = IOptimizedNFTMarket.BidOrder({
            bidder: bidder, tokenAddress: address(nft), tokenId: 1, price: 150, expiration: block.timestamp + 1 hours
        });
        bytes memory sig = _signOrder(order);

        vm.prank(user);
        market.acceptBid(order, sig);

        // re-list token 1 (bidder now owns it)
        vm.startPrank(bidder);
        nft.approve(address(market), 1);
        market.createListing(1, 200, 3600);
        vm.stopPrank();

        vm.prank(bidder);
        vm.expectRevert(bytes4(0x88b39043));
        market.acceptBid(order, sig);
    }

    // --- double sale blocked ---

    function test_flow_acceptBid_RevertsWhenAlreadySold() public {
        vm.prank(user);
        market.createListing(1, 100, 3600);

        IOptimizedNFTMarket.BidOrder memory order1 = IOptimizedNFTMarket.BidOrder({
            bidder: bidder, tokenAddress: address(nft), tokenId: 1, price: 150, expiration: block.timestamp + 1 hours
        });
        bytes memory sig1 = _signOrder(order1);

        vm.prank(user);
        market.acceptBid(order1, sig1);

        IOptimizedNFTMarket.BidOrder memory order2 = IOptimizedNFTMarket.BidOrder({
            bidder: bidder, tokenAddress: address(nft), tokenId: 1, price: 200, expiration: block.timestamp + 1 hours
        });
        bytes memory sig2 = _signOrder(order2);

        vm.prank(bidder);
        vm.expectRevert(bytes4(0x665c1c57));
        market.acceptBid(order2, sig2);
    }

    // --- storage slot collision proof ---

    function test_H1_slotCollision_fixed() public {
        uint24 tokenId = 7;
        address fakeUser = address(7);

        market.grantRole(fakeUser, 2);
        assertEq(market.getRoleOfUser(fakeUser), 2);

        nft.mint(user, tokenId);
        vm.prank(user);
        nft.approve(address(market), tokenId);
        vm.prank(user);
        market.createListing(tokenId, 100, 3600);

        // role must survive listing write
        assertEq(market.getRoleOfUser(fakeUser), 2);
    }

    // --- ownership transfer ---

    function test_flow_transferOwnership_newOwnerCanWithdraw() public {
        vm.prank(user);
        market.createListing(1, 1000, 3600);

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000);
        vm.prank(buyer);
        market.buyNow{value: 1000}(1);

        address newAdmin = makeAddr("newAdmin");
        market.transferOwnership(newAdmin);

        uint256 newAdminBal = newAdmin.balance;
        vm.prank(newAdmin);
        market.withdrawFees();
        assertGt(newAdmin.balance, newAdminBal);
    }

    function test_flow_transferOwnership_oldOwnerLosesAccess() public {
        address newAdmin = makeAddr("newAdmin");
        market.transferOwnership(newAdmin);

        vm.expectRevert(bytes4(0xeea91ff8));
        market.setFeeRate(100);
    }

    // --- nft transfer affects listing access ---

    function test_flow_afterTransfer_newOwnerCanList() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(user);
        nft.transferFrom(user, newOwner, 1);

        vm.startPrank(newOwner);
        nft.approve(address(market), 1);
        market.createListing(1, 1000, 3600);
        vm.stopPrank();
    }

    function test_flow_afterTransfer_oldOwnerCannotList() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(user);
        nft.transferFrom(user, newOwner, 1);

        vm.prank(user);
        vm.expectRevert(bytes4(0x59dc379f));
        market.createListing(1, 1000, 3600);
    }

    function test_flow_afterTransfer_newOwnerCanCancel() public {
        vm.prank(user);
        market.createListing(1, 1000, 3600);

        address newOwner = makeAddr("newOwner");
        vm.prank(user);
        nft.transferFrom(user, newOwner, 1);

        vm.prank(newOwner);
        market.cancelListing(1);
    }

    function test_flow_afterTransfer_oldOwnerCannotCancel() public {
        vm.prank(user);
        market.createListing(1, 1000, 3600);

        address newOwner = makeAddr("newOwner");
        vm.prank(user);
        nft.transferFrom(user, newOwner, 1);

        vm.prank(user);
        vm.expectRevert(bytes4(0x59dc379f));
        market.cancelListing(1);
    }

    // --- batch flow ---

    function test_flow_batchListThenBatchBuy() public {
        _batchListSetup();

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 600);

        uint24[] memory ids = new uint24[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        vm.prank(buyer);
        market.batchBuy{value: 600}(ids);

        assertEq(nft.ownerOf(1), buyer);
        assertEq(nft.ownerOf(2), buyer);
        assertEq(nft.ownerOf(3), buyer);
    }

    // --- re-list after cancel ---

    function test_flow_relistAfterCancel() public {
        vm.startPrank(user);
        market.createListing(1, 1000, 3600);
        market.cancelListing(1);
        market.createListing(1, 2000, 7200);
        vm.stopPrank();

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 2000);
        vm.prank(buyer);
        market.buyNow{value: 2000}(1);

        assertEq(nft.ownerOf(1), buyer);
    }
}
