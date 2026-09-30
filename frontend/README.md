# Pool Protocol — DeFi Frontend

React + TypeScript + Vite frontend for the Pool lending/borrowing protocol.

## Prerequisites
- Node.js 18+
- A running Anvil node: `anvil`
- Contracts deployed via `deploy.sh` (auto-writes `.env`)

## Quick Start

```bash
# 1. Install dependencies
npm install

# 2. Add contract addresses (deploy.sh does this automatically)
cp .env.example .env
# Edit .env with your deployed addresses

# 3. Start dev server
npm run dev
```

Open http://localhost:5173

## Build for Production

```bash
npm run build
npm run preview
```

## Stack
- React 18 + TypeScript
- Vite
- TailwindCSS
- wagmi v2 + viem
- TanStack Query v5
- sonner (toasts)

## Architecture
```
src/
├── types/        — Shared TypeScript models
├── lib/          — ABI, wagmi config, math utils
├── services/     — Contract interaction layer (poolService.ts)
├── hooks/        — Data fetching + transformation
│   ├── useReserves.ts
│   ├── usePositions.ts
│   ├── useHealthFactor.ts
│   └── useContract.ts
├── components/   — UI only (no contract logic)
│   ├── common/
│   ├── layout/
│   ├── reserves/
│   ├── positions/
│   └── borrow/
└── pages/        — MarketsPage, PositionsPage, BorrowPage
```


## Deployment compatibility

Set both `VITE_POOL_ADDRESS` and `VITE_POOL_CHAIN_ID` (114 for Coston2, 31337 for Anvil). The zero address disables protocol reads and writes. Writes require the wallet on that exact chain and a successful transaction receipt. Reads use the configured chain even when the wallet changes networks.

This frontend requires a fresh Pool exposing `getUserPositionIds(address)`, `getReserveTokenDecimals(bytes32)`, and `getPositionDebt(address,uint256)`. Existing deployed pools are not upgraded by a frontend build. Rebuild only after recording the address of the compatible deployment; do not reuse an old address automatically.

Position IDs are fetched at the same block as open position tuples, keeping repayment and health checks bound to original storage indexes. Token amounts use each reserve's decimals (0 through 18), and input beyond token precision is rejected. Health displays the contract's oracle-based boolean check; a numeric ratio is not available from the current Pool API. Debt reads preview accrued interest at the same block as the position. REPAY ALL sends the maximum repayment sentinel so the contract settles debt at execution time; token approval is capped at the current wallet balance, and the receipt-block open position IDs are checked to confirm closure before reporting full repayment. If interest accrues beyond available funds or allowance before execution, the transaction reverts; manual partial repayment remains available.

Run `npm test` with Node 24, then `npm run build`. CI should run `npm ci`, `npm test`, and `npm run build` from this directory.
