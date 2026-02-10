// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MarketSetup} from "./helpers/Setup.sol";

contract OptimizedNFTMarketFuzzTest is MarketSetup {
    function testFuzz_onlyOwnerCanList(address caller, uint24 tokenId, uint32 price, uint32 duration) public {
        vm.assume(caller != address(0));
        vm.assume(price > 0 && duration > 0);
        vm.assume(tokenId > 1);

        nft.mint(user, tokenId);
        vm.prank(user);
        nft.approve(address(market), tokenId);

        if (caller != user) {
            vm.prank(caller);
            vm.expectRevert(bytes4(0x59dc379f));
            market.createListing(tokenId, price, duration);
        } else {
            vm.prank(user);
            market.createListing(tokenId, price, duration);
        }
    }

    function testFuzz_marketMustBeApproved(uint24 tokenId, uint32 price, uint32 duration, bool approved) public {
        vm.assume(price > 0 && duration > 0);
        vm.assume(tokenId > 1);

        nft.mint(user, tokenId);

        if (approved) {
            vm.prank(user);
            nft.approve(address(market), tokenId);

            vm.prank(user);
            market.createListing(tokenId, price, duration);
        } else {
            vm.prank(user);
            vm.expectRevert(bytes4(0xc19f17a9));
            market.createListing(tokenId, price, duration);
        }
    }

    function testFuzz_buyNow_paymentMustMatchPrice(uint32 price, uint256 sent) public {
        vm.assume(price > 0);
        sent = bound(sent, 0, type(uint32).max);
        vm.assume(sent != price);

        vm.prank(user);
        market.createListing(1, price, 3600);

        address buyer = makeAddr("buyer");
        vm.deal(buyer, sent);

        vm.prank(buyer);
        vm.expectRevert();
        market.buyNow{value: sent}(1);
    }

    function testFuzz_buyNow_cannotBuyAfterExpiry(uint32 duration, uint32 warpExtra) public {
        vm.assume(duration > 0 && duration < type(uint32).max);
        warpExtra = uint32(bound(warpExtra, 1, type(uint32).max - duration));

        vm.prank(user);
        market.createListing(1, 100, duration);

        vm.warp(block.timestamp + uint256(duration) + uint256(warpExtra));

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 100);

        vm.prank(buyer);
        vm.expectRevert(bytes4(0x398cfd02));
        market.buyNow{value: 100}(1);
    }

    function testFuzz_cancelListing_onlyActive(uint32 price, uint32 duration) public {
        vm.assume(price > 0 && duration > 0);

        vm.startPrank(user);
        market.createListing(1, price, duration);
        market.cancelListing(1);

        vm.expectRevert(bytes4(0x665c1c57));
        market.cancelListing(1);
        vm.stopPrank();
    }

    function testFuzz_setFeeRate_cappedAt10000(uint256 feeRate) public {
        if (feeRate > 10000) {
            vm.expectRevert(bytes4(0xcd4e6167));
            market.setFeeRate(feeRate);
        } else {
            market.setFeeRate(feeRate);
        }
    }

    function testFuzz_grantRole_onlyValidRoles(address to, uint256 role) public {
        vm.assume(to != address(0));

        bool validRole = (role == 1 || role == 2 || role == 4);

        if (!validRole) {
            vm.expectRevert(bytes4(0xd954416a));
            market.grantRole(to, role);
        } else {
            market.grantRole(to, role);
            assertTrue(market.hasRole(to, role));
        }
    }
}
