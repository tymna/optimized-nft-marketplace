// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library Types {
    struct Listing {
        address seller; // 160
        uint32 price; // 32
        uint32 expiry; // 32
        uint8 status; // 8
        uint24 tokenId; // 24
    }
}
