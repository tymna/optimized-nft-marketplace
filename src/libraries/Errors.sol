// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library Errors {
    uint256 internal constant ZeroAddress = 0xd92e233d;
    // uint256 internal constant InvalidRole = 0xd954416a;
    // uint256 internal constant HasNoRole = 0x16c9d069;
    uint256 internal constant NotAnOwner = 0xeea91ff8;
    uint256 internal constant AlreadyOwner = 0xc0159e0e;
    uint256 internal constant CannotRevokeAdmin = 0xb462b2ec;
    uint256 internal constant NotTokenOwner = 0x59dc379f;
    uint256 internal constant NotApproved = 0xc19f17a9;
    uint256 internal constant InvalidSignature = 0x8baa579f;
}
