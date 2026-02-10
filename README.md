## Gas-Optimized NFT Marketplace

> **Disclaimer:** This project is an educational exercise in writing Solidity inline assembly (Yul) — not in a way to write for production smart contracts. The goal was to build a functional NFT marketplace using as much inline assembly as possible to demonstrate low-level EVM knowledge.

### Gas Comparison (Optimized vs Standard Solidity)

| | Deployment | createListing | buyNow | batchList | batchBuy |
|---|---|---|---|---|---|
| Optimized | 1,910,107 | 56,686 | 74,702 | 225,157 | 195,371 |
| Standard | 3,556,869 | 58,526 | 77,779 | 249,570 | 218,135 |
| **Savings** | **46.3%** | **3.1%** | **4.0%** | **9.8%** | **10.4%** |
