// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {OptimizedNFTMarket} from "../../src/OptimizedNFTMarket.sol";
import {IOptimizedNFTMarket} from "../../src/interfaces/IOptimizedNFTMarket.sol";

contract MockNFT {
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    function mint(address to, uint256 tokenId) external {
        ownerOf[tokenId] = to;
    }

    function approve(address spender, uint256 tokenId) external {
        getApproved[tokenId] = spender;
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == from, "Not owner");
        ownerOf[tokenId] = to;
        getApproved[tokenId] = address(0);
    }
}

contract MockWETH {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

abstract contract MarketSetup is Test {
    receive() external payable {}

    OptimizedNFTMarket market;
    MockNFT nft;
    MockWETH weth;

    address user = makeAddr("user");
    address admin;

    uint256 bidderPk = 0xBEEF;
    address bidder = vm.addr(bidderPk);

    bytes32 constant TYPEHASH = 0xec47fb701d2e69e338dc5bf05105d9c27e44fc14c1a3688f94e54ce93089eb38;

    function setUp() public virtual {
        admin = address(this);
        nft = new MockNFT();
        weth = new MockWETH();
        market = new OptimizedNFTMarket(address(nft), address(weth), admin);

        nft.mint(user, 1);
        vm.prank(user);
        nft.approve(address(market), 1);

        vm.deal(bidder, 10 ether);
        vm.startPrank(bidder);
        weth.deposit{value: 10 ether}();
        weth.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    function _mintAndApprove(address to, uint24 tokenId) internal {
        nft.mint(to, tokenId);
        vm.prank(to);
        nft.approve(address(market), tokenId);
    }

    function _signOrder(IOptimizedNFTMarket.BidOrder memory order) internal view returns (bytes memory) {
        return _signOrderWithKey(order, bidderPk);
    }

    function _signOrderWithKey(IOptimizedNFTMarket.BidOrder memory order, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(TYPEHASH, order.bidder, order.tokenAddress, order.tokenId, order.price, order.expiration)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", market.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _batchListSetup() internal {
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
}
