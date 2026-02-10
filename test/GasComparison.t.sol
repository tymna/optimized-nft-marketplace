// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {OptimizedNFTMarket} from "../src/OptimizedNFTMarket.sol";
import {SolidityNFTMarket} from "../src/SolidityNFTMarket.sol";
import {MockNFT, MockWETH} from "./helpers/Setup.sol";

contract GasComparisonTest is Test {
    receive() external payable {}

    OptimizedNFTMarket asm;
    SolidityNFTMarket sol;
    MockNFT nftAsm;
    MockNFT nftSol;
    MockWETH weth;

    address user = makeAddr("user");

    function setUp() public {
        nftAsm = new MockNFT();
        nftSol = new MockNFT();
        weth = new MockWETH();
        asm = new OptimizedNFTMarket(address(nftAsm), address(weth), address(this));
        sol = new SolidityNFTMarket(address(nftSol), address(weth), address(this));
    }

    function _setupToken(MockNFT nft, address market, uint24 tokenId) internal {
        nft.mint(user, tokenId);
        vm.prank(user);
        nft.approve(market, tokenId);
    }

    function _setupTokens(MockNFT nft, address market, uint24 count) internal {
        for (uint24 i = 1; i <= count; i++) {
            _setupToken(nft, market, i);
        }
    }

    // --- deployment ---

    function test_gas_deployment() public {
        uint256 g1 = gasleft();
        new OptimizedNFTMarket(address(nftAsm), address(weth), address(this));
        uint256 asmGas = g1 - gasleft();

        uint256 g2 = gasleft();
        new SolidityNFTMarket(address(nftSol), address(weth), address(this));
        uint256 solGas = g2 - gasleft();

        int256 savings = int256(solGas) - int256(asmGas);
        int256 pct = (savings * 100) / int256(solGas);

        console.log("=== deployment ===");
        console.log("  assembly:", asmGas);
        console.log("  solidity:", solGas);
        console.log("  savings :", uint256(savings > 0 ? savings : -savings));
        console.log("  percent :", pct > 0 ? string.concat(vm.toString(pct), "%") : "worse");
    }

    // --- createListing ---

    function test_gas_createListing() public {
        _setupToken(nftAsm, address(asm), 1);
        _setupToken(nftSol, address(sol), 1);

        vm.prank(user);
        uint256 g1 = gasleft();
        asm.createListing(1, 1000, 3600);
        uint256 asmGas = g1 - gasleft();

        vm.prank(user);
        uint256 g2 = gasleft();
        sol.createListing(1, 1000, 3600);
        uint256 solGas = g2 - gasleft();

        _logResult("createListing", asmGas, solGas);
    }

    // --- cancelListing ---

    function test_gas_cancelListing() public {
        _setupToken(nftAsm, address(asm), 1);
        _setupToken(nftSol, address(sol), 1);

        vm.prank(user);
        asm.createListing(1, 1000, 3600);
        vm.prank(user);
        sol.createListing(1, 1000, 3600);

        vm.prank(user);
        uint256 g1 = gasleft();
        asm.cancelListing(1);
        uint256 asmGas = g1 - gasleft();

        vm.prank(user);
        uint256 g2 = gasleft();
        sol.cancelListing(1);
        uint256 solGas = g2 - gasleft();

        _logResult("cancelListing", asmGas, solGas);
    }

    // --- buyNow ---

    function test_gas_buyNow() public {
        _setupToken(nftAsm, address(asm), 1);
        _setupToken(nftSol, address(sol), 1);

        vm.prank(user);
        asm.createListing(1, 1000, 3600);
        vm.prank(user);
        sol.createListing(1, 1000, 3600);

        address buyer1 = makeAddr("buyer1");
        address buyer2 = makeAddr("buyer2");
        vm.deal(buyer1, 1000);
        vm.deal(buyer2, 1000);

        vm.prank(buyer1);
        uint256 g1 = gasleft();
        asm.buyNow{value: 1000}(1);
        uint256 asmGas = g1 - gasleft();

        vm.prank(buyer2);
        uint256 g2 = gasleft();
        sol.buyNow{value: 1000}(1);
        uint256 solGas = g2 - gasleft();

        _logResult("buyNow", asmGas, solGas);
    }

    // --- batchList (3 items) ---

    function test_gas_batchList3() public {
        _setupTokens(nftAsm, address(asm), 3);
        _setupTokens(nftSol, address(sol), 3);

        uint24[] memory ids = new uint24[](3);
        ids[0] = 1; ids[1] = 2; ids[2] = 3;
        uint32[] memory prices = new uint32[](3);
        prices[0] = 100; prices[1] = 200; prices[2] = 300;

        vm.prank(user);
        uint256 g1 = gasleft();
        asm.batchList(ids, prices, 3600);
        uint256 asmGas = g1 - gasleft();

        vm.prank(user);
        uint256 g2 = gasleft();
        sol.batchList(ids, prices, 3600);
        uint256 solGas = g2 - gasleft();

        _logResult("batchList(3)", asmGas, solGas);
    }

    // --- batchBuy (3 items) ---

    function test_gas_batchBuy3() public {
        _setupTokens(nftAsm, address(asm), 3);
        _setupTokens(nftSol, address(sol), 3);

        uint24[] memory ids = new uint24[](3);
        ids[0] = 1; ids[1] = 2; ids[2] = 3;
        uint32[] memory prices = new uint32[](3);
        prices[0] = 100; prices[1] = 200; prices[2] = 300;

        vm.prank(user);
        asm.batchList(ids, prices, 3600);
        vm.prank(user);
        sol.batchList(ids, prices, 3600);

        address buyer1 = makeAddr("buyer1");
        address buyer2 = makeAddr("buyer2");
        vm.deal(buyer1, 600);
        vm.deal(buyer2, 600);

        vm.prank(buyer1);
        uint256 g1 = gasleft();
        asm.batchBuy{value: 600}(ids);
        uint256 asmGas = g1 - gasleft();

        vm.prank(buyer2);
        uint256 g2 = gasleft();
        sol.batchBuy{value: 600}(ids);
        uint256 solGas = g2 - gasleft();

        _logResult("batchBuy(3)", asmGas, solGas);
    }

    // --- batchList (10 items) ---

    function test_gas_batchList10() public {
        _setupTokens(nftAsm, address(asm), 10);
        _setupTokens(nftSol, address(sol), 10);

        uint24[] memory ids = new uint24[](10);
        uint32[] memory prices = new uint32[](10);
        for (uint24 i; i < 10; i++) {
            ids[i] = i + 1;
            prices[i] = (i + 1) * 100;
        }

        vm.prank(user);
        uint256 g1 = gasleft();
        asm.batchList(ids, prices, 3600);
        uint256 asmGas = g1 - gasleft();

        vm.prank(user);
        uint256 g2 = gasleft();
        sol.batchList(ids, prices, 3600);
        uint256 solGas = g2 - gasleft();

        _logResult("batchList(10)", asmGas, solGas);
    }

    // --- batchBuy (10 items) ---

    function test_gas_batchBuy10() public {
        _setupTokens(nftAsm, address(asm), 10);
        _setupTokens(nftSol, address(sol), 10);

        uint24[] memory ids = new uint24[](10);
        uint32[] memory prices = new uint32[](10);
        uint256 total;
        for (uint24 i; i < 10; i++) {
            ids[i] = i + 1;
            prices[i] = (i + 1) * 100;
            total += prices[i];
        }

        vm.prank(user);
        asm.batchList(ids, prices, 3600);
        vm.prank(user);
        sol.batchList(ids, prices, 3600);

        address buyer1 = makeAddr("buyer1");
        address buyer2 = makeAddr("buyer2");
        vm.deal(buyer1, total);
        vm.deal(buyer2, total);

        vm.prank(buyer1);
        uint256 g1 = gasleft();
        asm.batchBuy{value: total}(ids);
        uint256 asmGas = g1 - gasleft();

        vm.prank(buyer2);
        uint256 g2 = gasleft();
        sol.batchBuy{value: total}(ids);
        uint256 solGas = g2 - gasleft();

        _logResult("batchBuy(10)", asmGas, solGas);
    }

    // --- withdrawFees ---

    function test_gas_withdrawFees() public {
        _setupToken(nftAsm, address(asm), 1);
        _setupToken(nftSol, address(sol), 1);

        vm.prank(user);
        asm.createListing(1, 1000, 3600);
        vm.prank(user);
        sol.createListing(1, 1000, 3600);

        address buyer1 = makeAddr("buyer1");
        address buyer2 = makeAddr("buyer2");
        vm.deal(buyer1, 1000);
        vm.deal(buyer2, 1000);

        vm.prank(buyer1);
        asm.buyNow{value: 1000}(1);
        vm.prank(buyer2);
        sol.buyNow{value: 1000}(1);

        uint256 g1 = gasleft();
        asm.withdrawFees();
        uint256 asmGas = g1 - gasleft();

        uint256 g2 = gasleft();
        sol.withdrawFees();
        uint256 solGas = g2 - gasleft();

        _logResult("withdrawFees", asmGas, solGas);
    }

    // --- setFeeRate ---

    function test_gas_setFeeRate() public {
        uint256 g1 = gasleft();
        asm.setFeeRate(100);
        uint256 asmGas = g1 - gasleft();

        uint256 g2 = gasleft();
        sol.setFeeRate(100);
        uint256 solGas = g2 - gasleft();

        _logResult("setFeeRate", asmGas, solGas);
    }

    // --- helper ---

    function _logResult(string memory name, uint256 asmGas, uint256 solGas) internal pure {
        int256 savings = int256(solGas) - int256(asmGas);
        uint256 absSavings = savings > 0 ? uint256(savings) : uint256(-savings);
        int256 pct = (savings * 100) / int256(solGas);

        console.log(string.concat("=== ", name, " ==="));
        console.log("  assembly:", asmGas);
        console.log("  solidity:", solGas);
        console.log("  diff    :", absSavings);
        console.log("  savings :", pct > 0 ? string.concat(vm.toString(pct), "%") : string.concat("-", vm.toString(-pct), "%"));
    }
}
