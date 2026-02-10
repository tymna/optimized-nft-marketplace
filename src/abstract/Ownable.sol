// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Errors} from "../libraries/Errors.sol";

abstract contract Ownable {
    address private s_owner;

    constructor(address owner) {
        _transferOwnership(owner);
    }

    modifier onlyOwner() {
        if (msg.sender != getOwner()) _revert(Errors.NotAnOwner);
        _;
    }

    /* ───── EXTERNAL ───── */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == getOwner()) _revert(Errors.AlreadyOwner);
        _transferOwnership(newOwner);
    }

    /* ───── INTERNAL ───── */
    function _transferOwnership(address newOwner) internal {
        if (newOwner == address(0)) _revert(Errors.ZeroAddress);

        assembly {
            sstore(s_owner.slot, newOwner)
        }
    }

    function _revert(uint256 s) internal pure {
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04) // skip 28 bytes, load only error selector
        }
    }

    /* ───── GETTERS ───── */
    function getOwner() public view returns (address owner) {
        assembly {
            owner := sload(s_owner.slot)
        }
    }
}
