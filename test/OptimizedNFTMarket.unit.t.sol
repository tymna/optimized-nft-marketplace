// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MarketSetup} from "./helpers/Setup.sol";
import {IOptimizedNFTMarket} from "../src/interfaces/IOptimizedNFTMarket.sol";

contract OptimizedNFTMarketUnitTest is MarketSetup {
    // --- createListing ---

    function test_createListing_Works() public {
        vm.prank(user);
        market.createListing(1, 1000, 3600);
    }

    function test_createListing_RevertsWhenAlreadyListed() public {
        vm.startPrank(user);
        market.createListing(1, 1000, 3600);

        vm.expectRevert(bytes4(0xa3d582ec));
        market.createListing(1, 2000, 7200);
        vm.stopPrank();
    }

    function test_createListing_RevertsWhenPriceZero() public {
        vm.prank(user);
        vm.expectRevert(bytes4(0x00bfc921));
        market.createListing(1, 0, 3600);
    }

    function test_createListing_RevertsWhenDurationZero() public {
        vm.prank(user);
        vm.expectRevert(bytes4(0x76166401));
        market.createListing(1, 1000, 0);
    }

    function test_createListing_RevertsWhenNotTokenOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(bytes4(0x59dc379f));
        market.createListing(1, 1000, 3600);
    }

    function test_createListing_RevertsWhenNotApproved() public {
        nft.mint(user, 2);

        vm.prank(user);
        vm.expectRevert(bytes4(0xc19f17a9));
        market.createListing(2, 1000, 3600);
    }

    function test_createListing_CanOverwriteExpiredListing() public {
        vm.startPrank(user);
        market.createListing(1, 1000, 3600);
        vm.warp(block.timestamp + 3601);
        market.createListing(1, 2000, 7200);
        vm.stopPrank();
    }

    function test_createListing_CanOverwriteAtExactExpiry() public {
        vm.startPrank(user);
        market.createListing(1, 1000, 3600);
        vm.warp(block.timestamp + 3600);
        market.createListing(1, 2000, 7200);
        vm.stopPrank();
    }

    // --- cancelListing ---

    function test_cancelListing_Works() public {
        vm.startPrank(user);
        market.createListing(1, 1000, 3600);
        market.cancelListing(1);
        vm.stopPrank();
    }

    function test_cancelListing_RevertsWhenNotListed() public {
        vm.prank(user);
        vm.expectRevert(bytes4(0x665c1c57));
        market.cancelListing(1);
    }

    function test_cancelListing_RevertsWhenNotTokenOwner() public {
        vm.prank(user);
        market.createListing(1, 1000, 3600);

        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(bytes4(0x59dc379f));
        market.cancelListing(1);
    }

    // --- buyNow ---

    function test_buyNow_Works() public {
        vm.prank(user);
        market.createListing(1, 1000, 3600);

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 2000);
        vm.prank(buyer);
        market.buyNow{value: 1000}(1);

        assertEq(nft.ownerOf(1), buyer);
    }

    function test_buyNow_RevertsWhenNotListed() public {
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000);

        vm.prank(buyer);
        vm.expectRevert(bytes4(0x665c1c57));
        market.buyNow{value: 1000}(1);
    }

    function test_buyNow_RevertsWhenInsufficientPayment() public {
        vm.prank(user);
        market.createListing(1, 1000, 3600);

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 500);

        vm.prank(buyer);
        vm.expectRevert(bytes4(0xcd1c8867));
        market.buyNow{value: 500}(1);
    }

    function test_buyNow_RevertsWhenExpired() public {
        vm.prank(user);
        market.createListing(1, 1000, 3600);
        vm.warp(block.timestamp + 3601);

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000);

        vm.prank(buyer);
        vm.expectRevert(bytes4(0x398cfd02));
        market.buyNow{value: 1000}(1);
    }

    function test_buyNow_RevertsWhenAlreadySold() public {
        vm.prank(user);
        market.createListing(1, 1000, 3600);

        address buyer1 = makeAddr("buyer1");
        vm.deal(buyer1, 1000);
        vm.prank(buyer1);
        market.buyNow{value: 1000}(1);

        address buyer2 = makeAddr("buyer2");
        vm.deal(buyer2, 1000);
        vm.prank(buyer2);
        vm.expectRevert(bytes4(0x665c1c57));
        market.buyNow{value: 1000}(1);
    }

    function test_buyNow_RevertsWhenCanceled() public {
        vm.startPrank(user);
        market.createListing(1, 1000, 3600);
        market.cancelListing(1);
        vm.stopPrank();

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000);
        vm.prank(buyer);
        vm.expectRevert(bytes4(0x665c1c57));
        market.buyNow{value: 1000}(1);
    }

    function test_buyNow_SellerReceivesPayment() public {
        vm.prank(user);
        market.createListing(1, 1000, 3600);

        uint256 sellerBalanceBefore = user.balance;

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 2000);
        vm.prank(buyer);
        market.buyNow{value: 1000}(1);

        // 0.5% fee: 1000 - 5 = 995
        assertEq(user.balance, sellerBalanceBefore + 995);
    }

    // --- setFeeRate ---

    function test_setFeeRate_Works() public {
        market.setFeeRate(100);
    }

    function test_setFeeRate_RevertsWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert(bytes4(0xeea91ff8));
        market.setFeeRate(100);
    }

    function test_setFeeRate_RevertsWhenFeeTooHigh() public {
        vm.expectRevert(bytes4(0xcd4e6167));
        market.setFeeRate(10001);
    }

    // --- withdrawFees ---

    function test_withdrawFees_Works() public {
        vm.prank(user);
        market.createListing(1, 1000, 3600);

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000);
        vm.prank(buyer);
        market.buyNow{value: 1000}(1);

        uint256 adminBalBefore = admin.balance;
        market.withdrawFees();
        assertGt(admin.balance, adminBalBefore);
    }

    function test_withdrawFees_RevertsWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert(bytes4(0xeea91ff8));
        market.withdrawFees();
    }

    function test_withdrawFees_RevertsWhenNoFees() public {
        vm.expectRevert(bytes4(0x2002b183));
        market.withdrawFees();
    }

    // --- batchList ---

    function test_batchList_Works() public {
        _mintAndApprove(user, 2);
        _mintAndApprove(user, 3);

        uint24[] memory ids = new uint24[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        uint96[] memory prices = new uint96[](3);
        prices[0] = 100;
        prices[1] = 200;
        prices[2] = 300;

        vm.prank(user);
        market.batchList(ids, prices, 3600);
    }

    function test_batchList_RevertsWhenDurationZero() public {
        uint24[] memory ids = new uint24[](2);
        ids[0] = 1;
        ids[1] = 1;
        uint96[] memory prices = new uint96[](2);
        prices[0] = 100;
        prices[1] = 100;

        vm.prank(user);
        vm.expectRevert(bytes4(0x76166401));
        market.batchList(ids, prices, 0);
    }

    function test_batchList_RevertsWhenBatchTooBig() public {
        uint24[] memory ids = new uint24[](11);
        uint96[] memory prices = new uint96[](11);
        for (uint256 i; i < 11; i++) {
            ids[i] = uint24(i + 1);
            prices[i] = 100;
        }

        vm.prank(user);
        vm.expectRevert(bytes4(0xd0a7c351));
        market.batchList(ids, prices, 3600);
    }

    function test_batchList_RevertsWhenBatchTooSmall() public {
        uint24[] memory ids = new uint24[](1);
        ids[0] = 1;
        uint96[] memory prices = new uint96[](1);
        prices[0] = 100;

        vm.prank(user);
        vm.expectRevert(bytes4(0x7103b805));
        market.batchList(ids, prices, 3600);
    }

    function test_batchList_RevertsWhenLengthMismatch() public {
        uint24[] memory ids = new uint24[](2);
        ids[0] = 1;
        ids[1] = 2;
        uint96[] memory prices = new uint96[](3);
        prices[0] = 100;
        prices[1] = 200;
        prices[2] = 300;

        vm.prank(user);
        vm.expectRevert(bytes4(0xff633a38));
        market.batchList(ids, prices, 3600);
    }

    // --- batchCancel ---

    function test_batchCancel_Works() public {
        _batchListSetup();

        uint24[] memory ids = new uint24[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        vm.prank(user);
        market.batchCancel(ids);
    }

    function test_batchCancel_RevertsWhenNotListed() public {
        uint24[] memory ids = new uint24[](2);
        ids[0] = 1;
        ids[1] = 1;

        vm.prank(user);
        vm.expectRevert(bytes4(0x665c1c57));
        market.batchCancel(ids);
    }

    function test_batchCancel_RevertsWhenBatchTooBig() public {
        uint24[] memory ids = new uint24[](11);
        for (uint256 i; i < 11; i++) {
            ids[i] = uint24(i + 1);
        }

        vm.prank(user);
        vm.expectRevert(bytes4(0xd0a7c351));
        market.batchCancel(ids);
    }

    function test_batchCancel_RevertsWhenBatchTooSmall() public {
        uint24[] memory ids = new uint24[](1);
        ids[0] = 1;

        vm.prank(user);
        vm.expectRevert(bytes4(0x7103b805));
        market.batchCancel(ids);
    }

    function test_batchCancel_WorksWhenExpired() public {
        _batchListSetup();
        vm.warp(block.timestamp + 3601);

        uint24[] memory ids = new uint24[](2);
        ids[0] = 1;
        ids[1] = 2;

        vm.prank(user);
        market.batchCancel(ids);
    }

    // --- batchBuy ---

    function test_batchBuy_Works() public {
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

    function test_batchBuy_RevertsWhenNotListed() public {
        _mintAndApprove(user, 2);

        uint24[] memory ids = new uint24[](2);
        ids[0] = 1;
        ids[1] = 2;

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000);

        vm.prank(buyer);
        vm.expectRevert(bytes4(0x665c1c57));
        market.batchBuy{value: 1000}(ids);
    }

    function test_batchBuy_RevertsWhenExpired() public {
        _batchListSetup();
        vm.warp(block.timestamp + 3601);

        uint24[] memory ids = new uint24[](2);
        ids[0] = 1;
        ids[1] = 2;

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000);

        vm.prank(buyer);
        vm.expectRevert(bytes4(0x398cfd02));
        market.batchBuy{value: 1000}(ids);
    }

    function test_batchBuy_RevertsWhenBatchTooBig() public {
        uint24[] memory ids = new uint24[](11);
        for (uint256 i; i < 11; i++) {
            ids[i] = uint24(i + 1);
        }

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000);

        vm.prank(buyer);
        vm.expectRevert(bytes4(0xd0a7c351));
        market.batchBuy{value: 1000}(ids);
    }

    function test_batchBuy_RevertsWhenBatchTooSmall() public {
        uint24[] memory ids = new uint24[](1);
        ids[0] = 1;

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000);

        vm.prank(buyer);
        vm.expectRevert(bytes4(0x7103b805));
        market.batchBuy{value: 1000}(ids);
    }

    function test_batchBuy_SellerReceivesPayment() public {
        _batchListSetup();

        uint256 sellerBalanceBefore = user.balance;

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 600);

        uint24[] memory ids = new uint24[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        vm.prank(buyer);
        market.batchBuy{value: 600}(ids);

        // fees: 100*50/10000=0, 200*50/10000=1, 300*50/10000=1 → total 2
        assertEq(user.balance, sellerBalanceBefore + 598);
    }

    // --- acceptBid ---

    function test_acceptBid_RevertsWhenExpired() public {
        vm.prank(user);
        market.createListing(1, 100, 3600);

        IOptimizedNFTMarket.BidOrder memory order = IOptimizedNFTMarket.BidOrder({
            bidder: bidder, tokenAddress: address(nft), tokenId: 1, price: 150, expiration: block.timestamp - 1
        });
        bytes memory sig = _signOrder(order);

        vm.prank(user);
        vm.expectRevert(bytes4(0xcc6d1b44));
        market.acceptBid(order, sig);
    }

    function test_acceptBid_RevertsWhenNotListed() public {
        IOptimizedNFTMarket.BidOrder memory order = IOptimizedNFTMarket.BidOrder({
            bidder: bidder, tokenAddress: address(nft), tokenId: 1, price: 150, expiration: block.timestamp + 1 hours
        });
        bytes memory sig = _signOrder(order);

        vm.prank(user);
        vm.expectRevert(bytes4(0x665c1c57));
        market.acceptBid(order, sig);
    }

    function test_acceptBid_RevertsWhenListingCanceled() public {
        vm.startPrank(user);
        market.createListing(1, 100, 3600);
        market.cancelListing(1);
        vm.stopPrank();

        IOptimizedNFTMarket.BidOrder memory order = IOptimizedNFTMarket.BidOrder({
            bidder: bidder, tokenAddress: address(nft), tokenId: 1, price: 150, expiration: block.timestamp + 1 hours
        });
        bytes memory sig = _signOrder(order);

        vm.prank(user);
        vm.expectRevert(bytes4(0x665c1c57));
        market.acceptBid(order, sig);
    }

    function test_acceptBid_RevertsWhenListingExpired() public {
        vm.prank(user);
        market.createListing(1, 100, 1 hours);
        vm.warp(block.timestamp + 2 hours);

        IOptimizedNFTMarket.BidOrder memory order = IOptimizedNFTMarket.BidOrder({
            bidder: bidder, tokenAddress: address(nft), tokenId: 1, price: 150, expiration: block.timestamp + 1 hours
        });
        bytes memory sig = _signOrder(order);

        vm.prank(user);
        vm.expectRevert(bytes4(0x398cfd02));
        market.acceptBid(order, sig);
    }

    function test_acceptBid_RevertsWhenWrongTokenAddress() public {
        vm.prank(user);
        market.createListing(1, 100, 3600);

        IOptimizedNFTMarket.BidOrder memory order = IOptimizedNFTMarket.BidOrder({
            bidder: bidder, tokenAddress: address(0xDEAD), tokenId: 1, price: 150, expiration: block.timestamp + 1 hours
        });
        bytes memory sig = _signOrder(order);

        vm.prank(user);
        vm.expectRevert(bytes4(0x28716b92));
        market.acceptBid(order, sig);
    }

    function test_acceptBid_RevertsWhenWrongSigner() public {
        vm.prank(user);
        market.createListing(1, 100, 3600);

        IOptimizedNFTMarket.BidOrder memory order = IOptimizedNFTMarket.BidOrder({
            bidder: bidder, tokenAddress: address(nft), tokenId: 1, price: 150, expiration: block.timestamp + 1 hours
        });
        bytes memory wrongSig = _signOrderWithKey(order, 0xDEAD);

        vm.prank(user);
        vm.expectRevert(bytes4(0x8baa579f));
        market.acceptBid(order, wrongSig);
    }

    function test_acceptBid_RevertsWhenBidderHasNoWETH() public {
        uint256 brokePk = 0xCAFE;
        address brokeBidder = vm.addr(brokePk);

        vm.prank(user);
        market.createListing(1, 100, 3600);

        IOptimizedNFTMarket.BidOrder memory order = IOptimizedNFTMarket.BidOrder({
            bidder: brokeBidder,
            tokenAddress: address(nft),
            tokenId: 1,
            price: 150,
            expiration: block.timestamp + 1 hours
        });
        bytes memory sig = _signOrderWithKey(order, brokePk);

        vm.prank(user);
        vm.expectRevert();
        market.acceptBid(order, sig);
    }

    function test_acceptBid_RevertsWhenNotApproved() public {
        uint256 noApprovePk = 0xFACE;
        address noApproveBidder = vm.addr(noApprovePk);
        vm.deal(noApproveBidder, 1 ether);
        vm.prank(noApproveBidder);
        weth.deposit{value: 1 ether}();

        vm.prank(user);
        market.createListing(1, 100, 3600);

        IOptimizedNFTMarket.BidOrder memory order = IOptimizedNFTMarket.BidOrder({
            bidder: noApproveBidder,
            tokenAddress: address(nft),
            tokenId: 1,
            price: 150,
            expiration: block.timestamp + 1 hours
        });
        bytes memory sig = _signOrderWithKey(order, noApprovePk);

        vm.prank(user);
        vm.expectRevert();
        market.acceptBid(order, sig);
    }

    // --- price range / expiry ---

    function test_buyNow_PriceAboveUint32() public {
        uint96 price = 10 ether;
        vm.prank(user);
        market.createListing(1, price, 3600);

        address buyer = makeAddr("buyer");
        vm.deal(buyer, price);
        uint256 sellerBalanceBefore = user.balance;

        vm.prank(buyer);
        market.buyNow{value: price}(1);

        assertEq(nft.ownerOf(1), buyer);
        assertEq(user.balance, sellerBalanceBefore + price - (price * 50) / 10000);
    }

    function test_createListing_RevertsWhenExpiryOverflows() public {
        vm.prank(user);
        vm.expectRevert(bytes4(0x76166401));
        market.createListing(1, 100, type(uint32).max);
    }

    // --- signature malleability / replay ---

    function test_acceptBid_RevertsWhenHighS() public {
        vm.prank(user);
        market.createListing(1, 100, 3600);

        IOptimizedNFTMarket.BidOrder memory order = IOptimizedNFTMarket.BidOrder({
            bidder: bidder, tokenAddress: address(nft), tokenId: 1, price: 150, expiration: block.timestamp + 1 hours
        });
        bytes memory sig = _signOrder(order);

        // same signature in its high-s form: s' = n - s, v flipped
        bytes32 r;
        bytes32 sLow;
        uint8 v;
        assembly {
            r := mload(add(sig, 0x20))
            sLow := mload(add(sig, 0x40))
            v := byte(0, mload(add(sig, 0x60)))
        }
        uint256 n = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;
        bytes memory highSig = abi.encodePacked(r, bytes32(n - uint256(sLow)), v == 27 ? uint8(28) : uint8(27));

        vm.prank(user);
        vm.expectRevert(bytes4(0x8baa579f));
        market.acceptBid(order, highSig);
    }

    function test_acceptBid_StoresOrderInUsedOrders() public {
        vm.prank(user);
        market.createListing(1, 100, 3600);

        IOptimizedNFTMarket.BidOrder memory order = IOptimizedNFTMarket.BidOrder({
            bidder: bidder, tokenAddress: address(nft), tokenId: 1, price: 150, expiration: block.timestamp + 1 hours
        });
        bytes memory sig = _signOrder(order);

        vm.prank(user);
        market.acceptBid(order, sig);

        bytes32 structHash = keccak256(
            abi.encode(TYPEHASH, order.bidder, order.tokenAddress, order.tokenId, order.price, order.expiration)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", market.DOMAIN_SEPARATOR(), structHash));

        // s_usedOrders is storage slot 3
        assertEq(uint256(vm.load(address(market), keccak256(abi.encode(digest, uint256(3))))), 1);
    }
}
