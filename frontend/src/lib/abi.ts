/**
 * ABI fragments matching contracts/src/interfaces/IPool.sol and
 * contracts/src/libraries/DataTypes.sol exactly as of the Week 1-4 changes
 * (bytes32 reserve/position IDs, FtsoOracle-compatible reserve shape).
 *
 * Struct field ORDER matters — wagmi/viem decode tuples positionally, not
 * by name, so this must mirror DataTypes.ReserveData / DataTypes.Position
 * field-for-field. If those structs change, this needs to change with them
 * (consider running `forge inspect Pool abi` and diffing against this file
 * after any contract change that touches reserve/position shape).
 *
 * Note: `getUserDepositBalance`/`getUserBorrowBalance` are declared `view`
 * here even though IPool.sol declares them plain `external` (they call
 * `updateIndexes` internally, which writes state) — this frontend only ever
 * calls them through `readContract`, i.e. as an `eth_call` that can't
 * persist state regardless of the ABI's stated mutability. Declaring them
 * `view` here is what lets wagmi's typed `readContract` accept them; it has
 * no effect on the deployed contract's actual behavior.
 */

const reserveDataComponents = [
  { name: 'id', type: 'bytes32' },
  { name: 'reserveName', type: 'string' },
  { name: 'tokenAddress', type: 'address' },
  { name: 'priceFeed', type: 'address' },
  { name: 'interestStrategy', type: 'address' },
  { name: 'liquidationThreshold', type: 'uint256' },
  { name: 'ltv', type: 'uint256' },
  { name: 'slope1', type: 'uint256' },
  { name: 'slope2', type: 'uint256' },
  { name: 'baseInterestRate', type: 'uint256' },
  { name: 'optimalUtilization', type: 'uint256' },
  { name: 'liquidationBonus', type: 'uint256' },
  { name: 'reserveFactor', type: 'uint256' },
  { name: 'borrowCap', type: 'uint256' },
  { name: 'supplyCap', type: 'uint256' },
  { name: 'totalDeposits', type: 'uint256' },
  { name: 'totalBorrows', type: 'uint256' },
  { name: 'supplyLiquidityIndex', type: 'uint256' },
  { name: 'borrowLiquidityIndex', type: 'uint256' },
  { name: 'lastUpdateTimestamp', type: 'uint256' },
  { name: 'isActive', type: 'bool' },
  { name: 'isBorrowable', type: 'bool' },
] as const

const positionComponents = [
  { name: 'collateralReserveId', type: 'bytes32' },
  { name: 'borrowReserveId', type: 'bytes32' },
  { name: 'collateralPriceFeed', type: 'address' },
  { name: 'borrowPriceFeed', type: 'address' },
  { name: 'scaledDebt', type: 'uint256' },
  { name: 'collateralLocked', type: 'uint256' },
  { name: 'bufferPercent', type: 'uint256' },
  { name: 'isOpen', type: 'bool' },
] as const

export const POOL_ABI = [
  // ── Core user actions ──────────────────────────────────────────
  {
    type: 'function',
    name: 'deposit',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'reserveId', type: 'bytes32' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'withdraw',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'reserveId', type: 'bytes32' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'borrow',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'collateralId', type: 'bytes32' },
      { name: 'borrowId', type: 'bytes32' },
      { name: 'amount', type: 'uint256' },
      { name: 'bufferPercent', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'repay',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'collateralId', type: 'bytes32' },
      { name: 'borrowId', type: 'bytes32' },
      { name: 'positionId', type: 'uint256' },
      { name: 'repayAmount', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'liquidate',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'user', type: 'address' },
      { name: 'positionId', type: 'uint256' },
    ],
    outputs: [],
  },
  // ── Views ───────────────────────────────────────────────────────
  {
    type: 'function',
    name: 'getReserve',
    stateMutability: 'view',
    inputs: [{ name: 'reserveId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'tuple', components: reserveDataComponents }],
  },
  {
    type: 'function',
    name: 'getAllReserves',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'tuple[]', components: reserveDataComponents }],
  },
  {
    type: 'function',
    name: 'getReserveId',
    stateMutability: 'pure',
    inputs: [{ name: 'name', type: 'string' }],
    outputs: [{ name: '', type: 'bytes32' }],
  },
  {
    type: 'function',
    name: 'getUserDepositBalance',
    stateMutability: 'view', // called only via readContract/eth_call in this frontend; see note below
    inputs: [
      { name: 'reserveId', type: 'bytes32' },
      { name: 'user', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'getUserBorrowBalance',
    stateMutability: 'view',
    inputs: [
      { name: 'reserveId', type: 'bytes32' },
      { name: 'user', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'getUtilizationRate',
    stateMutability: 'view',
    inputs: [{ name: 'reserveId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'getUserPositions',
    stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ name: '', type: 'tuple[]', components: positionComponents }],
  },
  {
    type: 'function',
    name: 'checkPositionHealth',
    stateMutability: 'view',
    inputs: [
      { name: 'user', type: 'address' },
      { name: 'positionId', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  // ── Events ──────────────────────────────────────────────────────
  {
    type: 'event',
    name: 'Deposit',
    inputs: [
      { name: 'user', type: 'address', indexed: true },
      { name: 'reserveId', type: 'bytes32', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'scaledAmount', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'Borrow',
    inputs: [
      { name: 'user', type: 'address', indexed: true },
      { name: 'borrowReserveId', type: 'bytes32', indexed: true },
      { name: 'collateralReserveId', type: 'bytes32', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'collateralLocked', type: 'uint256', indexed: false },
      { name: 'positionId', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'Liquidated',
    inputs: [
      { name: 'user', type: 'address', indexed: true },
      { name: 'liquidator', type: 'address', indexed: true },
      { name: 'collateralReserveId', type: 'bytes32', indexed: true },
      { name: 'borrowReserveId', type: 'bytes32', indexed: false },
      { name: 'debtRepaid', type: 'uint256', indexed: false },
      { name: 'collateralSeized', type: 'uint256', indexed: false },
      { name: 'positionId', type: 'uint256', indexed: false },
    ],
  },
] as const

export const ERC20_ABI = [
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'allowance',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'approve',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    type: 'function',
    name: 'decimals',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint8' }],
  },
] as const
