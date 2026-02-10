// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRoleManager} from "../interfaces/IRoleManager.sol";
import {Errors} from "../libraries/Errors.sol";
import {Ownable} from "./Ownable.sol";

// ivariant: owner is always an admin
abstract contract RoleManager is IRoleManager, Ownable {
    mapping(address user => uint256 role) private s_userRole;

    uint256 private constant ADMIN_ROLE = 1;
    uint256 private constant CREATOR_ROLE = 2;
    uint256 private constant VERIFIED_ROLE = 4;

    constructor(address admin) Ownable(admin) {
        bytes32 userSlot = _getUserSlot(admin);
        assembly {
            sstore(userSlot, ADMIN_ROLE)
        }
    }

    /* ───── EXTERNAL ───── */
    function grantRole(address to, uint256 role) external onlyOwner {
        if (to == address(0)) _revert(Errors.ZeroAddress);
        bytes32 userSlot = _getUserSlot(to);

        assembly {
            let valid := or(eq(role, 4), or(eq(role, 1), eq(role, 2)))

            if iszero(valid) {
                mstore(0x00, 0xd954416a) // "InvalidRole()"
                revert(0x1c, 0x04)
            }

            let current := sload(userSlot)
            sstore(userSlot, or(current, role))

            mstore(0x00, to)
            mstore(0x20, role)
            log3(0x00, 0x00, 0x179d9faeef78652d6b82f73b6ad9bf53b5b05d2a7f212a4ef46cb7b7d3c123db, to, role) // "RoleGranted(address,uint256)"
            // to, role are indexed params
        }
    }

    function revokeRole(address user, uint256 role) external onlyOwner {
        if (user == address(0)) _revert(Errors.ZeroAddress);
        bytes32 userSlot = _getUserSlot(user);

        assembly {
            let valid := or(eq(role, 4), or(eq(role, 1), eq(role, 2)))
            if iszero(valid) {
                mstore(0x00, 0xd954416a) // InvalidRole()
                revert(0x1c, 0x04)
            }

            // cannot revoke ADMIN_ROLE
            if eq(role, 1) {
                mstore(0x00, 0xb462b2ec) // CannotRevokeAdmin()
                revert(0x1c, 0x04)
            }

            let currentRole := sload(userSlot)

            // user must actually have this role bit set
            if iszero(and(currentRole, role)) {
                mstore(0x00, 0x16c9d069) // HasNoRole()
                revert(0x1c, 0x04)
            }

            // clear the specific bit
            sstore(userSlot, and(currentRole, not(role)))
            log3(0x00, 0x00, 0x12982f922b0573398129ea86655ce1e8e425ec676c9e3d40bf5458688b1ef544, user, role) // "RoleRevoked(address,uint256)"
        }
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        address oldOwner = getOwner();
        super.transferOwnership(newOwner);

        bytes32 oldSlot = _getUserSlot(oldOwner);
        bytes32 newSlot = _getUserSlot(newOwner);

        assembly {
            sstore(oldSlot, 0) // remove admin from old owner
            sstore(newSlot, 1) // give admin to new owner

            mstore(0x00, oldOwner)
            mstore(0x20, newOwner)
            log3(0x00, 0x00, 0x8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0, oldOwner, newOwner) // "OwnershipTransferred(address,address)"
        }
    }

    /* ───── INTERNAL ───── */
    function _getUserSlot(address user) internal pure returns (bytes32 slot) {
        assembly {
            mstore(0x00, user)
            mstore(0x20, s_userRole.slot)
            slot := keccak256(0x00, 0x40)
        }
    }

    /* ───── GETTERS ───── */
    function getRoleOfUser(address user) external view returns (uint256 role) {
        bytes32 slot = _getUserSlot(user);
        assembly {
            role := sload(slot)
        }
    }

    function getAdminRole() external pure returns (uint256) {
        return ADMIN_ROLE;
    }

    function getCreatorRole() external pure returns (uint256) {
        return CREATOR_ROLE;
    }

    function getVerifiedRole() external pure returns (uint256) {
        return VERIFIED_ROLE;
    }

    function hasRole(address user, uint256 role) external view returns (bool _hasRole) {
        bytes32 slot = _getUserSlot(user);
        assembly {
            let _role := sload(slot)
            _hasRole := gt(and(_role, role), 0) // check if bit is set
        }
    }
}
