## Gas-Optimized NFT Marketplace

> **Disclaimer:** This project is an educational exercise in writing Solidity inline assembly (Yul) — not in a way to write for production smart contracts. The goal was to build a functional NFT marketplace using as much inline assembly as possible to demonstrate low-level EVM knowledge.

### Gas Comparison (Optimized vs Standard Solidity)

| | Deployment | createListing | buyNow | batchList | batchBuy |
|---|---|---|---|---|---|
| Optimized | 1,947,719 | 78,842 | 76,755 | 369,144 | 209,044 |
| Standard | 3,617,275 | 80,399 | 79,709 | 391,652 | 230,801 |
| **Savings** | **46.2%** | **1.9%** | **3.7%** | **5.7%** | **9.4%** |
