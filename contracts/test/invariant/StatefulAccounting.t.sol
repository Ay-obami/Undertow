// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PoolTestBase} from "../unit/PoolTestBase.sol";
import {Pool} from "../../src/modules/Pool.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockOracle} from "../mocks/MockOracle.sol";

// Test-only access to the individual ledgers, not an alternate accounting implementation.
contract AccountingProbe is Pool {
    constructor(address oracle_) Pool(oracle_) {}

    function accrue(bytes32 id) external {
        _accrueReserve(id);
    }

    function scaledDeposit(bytes32 id, address user) external view returns (uint256) {
        return _scaledDeposits[id][user];
    }

    function totals(bytes32 id) external view returns (uint256, uint256, uint256) {
        return (_totalScaledDeposits[id], _totalScaledDebt[id], _totalLockedCollateral[id]);
    }

    function historicalPosition(address user, uint256 id) external view returns (DataTypes.Position memory) {
        return _positions[user][id];
    }
}

contract AccountingHandler is Test {
    AccountingProbe public pool;
    MockOracle public oracle;
    MockERC20[2] public tokens;
    bytes32[2] public ids;
    address[3] public actors;
    uint256[3] public positionCount;
    uint256[2] public ghostCash;
    uint256[7] public successes; // deposit, withdraw, borrow, repay, liquidate, clock/price, rollback
    uint256 public startTime;
    uint256 public transitions;
    address public feed;

    constructor(
        AccountingProbe p,
        MockOracle o,
        MockERC20 dollar,
        MockERC20 collateral,
        bytes32 dollarId,
        bytes32 collateralId,
        address collateralFeed
    ) {
        pool = p;
        oracle = o;
        tokens[0] = dollar;
        tokens[1] = collateral;
        ids[0] = dollarId;
        ids[1] = collateralId;
        feed = collateralFeed;
        startTime = block.timestamp;
        for (uint256 a; a < 3; ++a) {
            actors[a] = address(uint160(0xA100 + a));
            dollar.mint(actors[a], 500_000e18);
            collateral.mint(actors[a], 500e18);
            vm.startPrank(actors[a]);
            dollar.approve(address(p), type(uint256).max);
            collateral.approve(address(p), type(uint256).max);
            p.deposit(dollarId, 100_000e18);
            p.deposit(collateralId, 100e18);
            vm.stopPrank();
        }
        ghostCash[0] = 300_000e18;
        ghostCash[1] = 300e18;
    }

    function deposit(uint256 actorSeed, uint256 assetSeed, uint256 amountSeed) public {
        uint256 a = actorSeed % 3;
        uint256 r = assetSeed % 2;
        uint256 amount = bound(amountSeed, 1e12, r == 0 ? 100e18 : 1e18);
        if (tokens[r].balanceOf(actors[a]) < amount) return;
        if (pool.getReserve(ids[r]).totalDeposits + amount > 900_000e18) return;
        vm.prank(actors[a]);
        pool.deposit(ids[r], amount);
        ghostCash[r] += amount;
        ++successes[0];
        ++transitions;
    }

    function withdraw(uint256 actorSeed, uint256 assetSeed, uint256 fractionSeed) public {
        uint256 a = actorSeed % 3;
        uint256 r = assetSeed % 2;
        uint256 claim = pool.getUserDepositBalance(ids[r], actors[a]);
        uint256 amount = claim * bound(fractionSeed, 1, 10_000) / 10_000;
        if (amount == 0 || amount > ghostCash[r]) return;
        vm.prank(actors[a]);
        pool.withdraw(ids[r], amount);
        ghostCash[r] -= amount;
        ++successes[1];
        ++transitions;
    }

    function borrow(uint256 actorSeed, uint256 amountSeed) public {
        uint256 a = actorSeed % 3;
        if (positionCount[a] >= 64) return;
        // Conservative preconditions; unexpected protocol reverts fail the invariant run.
        uint256 amount = bound(amountSeed, 10e18, 1_000e18);
        if (pool.getUserDepositBalance(ids[1], actors[a]) < 2e18) return;
        DataTypes.ReserveData memory r = pool.getReserve(ids[0]);
        if (r.totalBorrows + amount > r.totalDeposits / 2 || ghostCash[0] < amount) return;
        vm.prank(actors[a]);
        pool.borrow(ids[1], ids[0], amount, 0.05e18);
        ++positionCount[a];
        ghostCash[0] -= amount;
        ++successes[2];
        ++transitions;
    }

    function repay(uint256 actorSeed, uint256 positionSeed, uint256 fractionSeed) public {
        uint256 a = actorSeed % 3;
        if (positionCount[a] == 0) return;
        uint256 posId = positionSeed % positionCount[a];
        DataTypes.Position memory p = pool.historicalPosition(actors[a], posId);
        if (!p.isOpen) return;
        pool.accrue(ids[0]);
        pool.accrue(ids[1]);
        uint256 debt = (p.scaledDebt * pool.getReserve(ids[0]).borrowLiquidityIndex + 0.5e18) / 1e18;
        uint256 amount = debt * bound(fractionSeed, 1, 10_000) / 10_000;
        if (amount < 1 + pool.getReserve(ids[0]).borrowLiquidityIndex / 1e18 || tokens[0].balanceOf(actors[a]) < amount)
        {
            return;
        }
        vm.prank(actors[a]);
        pool.repay(ids[1], ids[0], posId, amount);
        ghostCash[0] += amount;
        ++successes[3];
        ++transitions;
    }

    function liquidate(uint256 actorSeed, uint256 positionSeed) public {
        uint256 a = actorSeed % 3;
        if (positionCount[a] == 0) return;
        uint256 posId = positionSeed % positionCount[a];
        DataTypes.Position memory p = pool.historicalPosition(actors[a], posId);
        if (!p.isOpen || p.collateralLocked < 1e12) return;
        pool.accrue(ids[0]);
        pool.accrue(ids[1]);
        uint256 debt = (p.scaledDebt * pool.getReserve(ids[0]).borrowLiquidityIndex + 0.5e18) / 1e18;
        uint256 payer = (a + 1) % 3;
        if (tokens[0].balanceOf(actors[payer]) < debt) return;
        // Collateral value = 110% of debt: unhealthy at 85% threshold,
        // but sufficient for the 105% liquidation payment, even after rounding.
        oracle.setPrice(feed, debt * 1e18 / p.collateralLocked * 110 / 100);
        vm.prank(actors[payer]);
        pool.liquidate(actors[a], posId);
        oracle.setPrice(feed, 3_000e18);
        ghostCash[0] += debt;
        ghostCash[1] -= p.collateralLocked;
        ++successes[4];
        ++transitions;
    }

    function clockAndPrice(uint256 elapsedSeed, uint256 priceSeed) public {
        uint256 elapsed = bound(elapsedSeed, 0, 7 days);
        uint256 nextTime = block.timestamp + elapsed;
        if (nextTime > startTime + 365 days) nextTime = startTime + 365 days;
        vm.warp(nextTime);
        oracle.setPrice(feed, bound(priceSeed, 2_500e18, 3_500e18));
        pool.accrue(ids[0]);
        pool.accrue(ids[1]);
        ++successes[5];
    }

    function revertRollback(uint256 actorSeed, uint256 assetSeed) public {
        uint256 a = actorSeed % 3;
        uint256 r = assetSeed % 2;
        bytes32 beforeState = keccak256(
            abi.encode(
                pool.getReserve(ids[r]),
                pool.scaledDeposit(ids[r], actors[a]),
                tokens[r].balanceOf(actors[a]),
                ghostCash[r]
            )
        );
        uint256 invalidAmount = pool.getUserDepositBalance(ids[r], actors[a]) + 1;
        vm.prank(actors[a]);
        (bool ok,) = address(pool).call(abi.encodeCall(Pool.withdraw, (ids[r], invalidAmount)));
        assertFalse(ok, "overwithdraw accepted");
        assertEq(
            keccak256(
                abi.encode(
                    pool.getReserve(ids[r]),
                    pool.scaledDeposit(ids[r], actors[a]),
                    tokens[r].balanceOf(actors[a]),
                    ghostCash[r]
                )
            ),
            beforeState
        );
        ++successes[6];
    }

    function assertAccounting() public view {
        for (uint256 r; r < 2; ++r) {
            uint256 deposits;
            uint256 scaledDebt;
            uint256 locks;
            uint256 freeClaims;
            uint256 debtClaims;
            uint256 openCount;
            DataTypes.ReserveData memory reserve = pool.getReserve(ids[r]);
            for (uint256 a; a < 3; ++a) {
                deposits += pool.scaledDeposit(ids[r], actors[a]);
                freeClaims += pool.getUserDepositBalance(ids[r], actors[a]);
                debtClaims += pool.getUserBorrowBalance(ids[r], actors[a]);
                for (uint256 i; i < positionCount[a]; ++i) {
                    DataTypes.Position memory p = pool.historicalPosition(actors[a], i);
                    if (!p.isOpen) {
                        assertEq(p.scaledDebt, 0);
                        assertEq(p.collateralLocked, 0);
                        continue;
                    }
                    if (p.collateralReserveId == ids[r]) locks += p.collateralLocked;
                    if (p.borrowReserveId == ids[r]) {
                        scaledDebt += p.scaledDebt;
                        ++openCount;
                    }
                }
            }
            (uint256 totalDeposits, uint256 totalDebt, uint256 totalLocks) = pool.totals(ids[r]);
            assertEq(totalDeposits, deposits, "lost individual scaled supply");
            assertEq(totalDebt, scaledDebt, "lost individual scaled debt");
            assertEq(totalLocks, locks, "lost fixed collateral");
            // Each independently rounded account/position contributes at most one native unit.
            assertApproxEqAbs(reserve.totalDeposits, freeClaims + locks, 3);
            assertApproxEqAbs(reserve.totalBorrows, debtClaims, openCount);
            assertEq(tokens[r].balanceOf(address(pool)), ghostCash[r], "unexpected token flow");
            assertGe(ghostCash[r], locks, "fixed collateral not held in custody");
            uint256 bound_ = (transitions + openCount + 3)
                * (1 + reserve.supplyLiquidityIndex / 1e18 + reserve.borrowLiquidityIndex / 1e18);
            assertGe(ghostCash[r] + debtClaims + bound_, freeClaims + locks, "unbacked claims");
        }
    }
}

contract StatefulAccountingTest is PoolTestBase {
    AccountingHandler internal handler;

    function setUp() public override {
        super.setUp();
        pool = new AccountingProbe(address(oracle));
        _addReserve("mUSDT", address(usdt), usdtFeed);
        _addReserve("mWETH", address(weth), wethFeed);
        handler = new AccountingHandler(AccountingProbe(address(pool)), oracle, usdt, weth, USDT_ID, WETH_ID, wethFeed);
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.withdraw.selector;
        selectors[2] = handler.borrow.selector;
        selectors[3] = handler.repay.selector;
        selectors[4] = handler.liquidate.selector;
        selectors[5] = handler.clockAndPrice.selector;
        selectors[6] = handler.revertRollback.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_IndividualLedgersAndCashBackAllClaims() public view {
        handler.assertAccounting();
    }

    // Prevent a vacuous all-skipped handler from being mistaken for scenario coverage.
    function test_HandlerExercisesEveryActionAndClosedPositions() public {
        handler.deposit(0, 0, 100e18);
        handler.borrow(0, 1_000e18);
        handler.borrow(1, 700e18);
        handler.clockAndPrice(37 days, 2_700e18);
        handler.repay(0, 0, 5_000);
        handler.repay(0, 0, 10_000);
        handler.liquidate(1, 0);
        handler.withdraw(0, 1, 5_000);
        handler.withdraw(2, 1, 10_000);
        handler.revertRollback(0, 0);
        handler.assertAccounting();
        for (uint256 i; i < 7; ++i) {
            assertGt(handler.successes(i), 0);
        }
        assertEq(pool.getUserBorrowBalance(USDT_ID, handler.actors(0)), 0);
        assertEq(pool.getUserBorrowBalance(USDT_ID, handler.actors(1)), 0);
        assertEq(pool.getUserDepositBalance(WETH_ID, handler.actors(2)), 0);
    }
}
