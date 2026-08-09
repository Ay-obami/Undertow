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
