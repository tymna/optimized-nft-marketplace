// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IRoleManager {
    function grantRole(address to, uint256 role) external;
    function revokeRole(address user, uint256 role) external;
    function getRoleOfUser(address user) external view returns (uint256 role);
    function getAdminRole() external view returns (uint256 roleNum);
    function getCreatorRole() external view returns (uint256 roleNum);
    function getVerifiedRole() external view returns (uint256 roleNum);
}
