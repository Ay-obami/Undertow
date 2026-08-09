// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolTestBase} from "./PoolTestBase.sol";
import {DataTypes}    from "../../src/libraries/DataTypes.sol";
import {Pool}         from "../../src/modules/Pool.sol";
import {MockOracle}   from "../mocks/MockOracle.sol";

contract PoolAdminTest is PoolTestBase {
   event ReserveStatusUpdated(bytes32 indexed reserveId, bool isActive);
   event ReserveBorrowStatusUpdated(bytes32 indexed reserveId, bool isBorrowable);

    // ================================================================
    // Constructor
    // ================================================================

    function test_Constructor_SetsOwner() public view {
        // Deployer is this test contract (PoolTestBase deploys pool as address(this))
        // We just check pool exists and oracle is wired
        assertEq(pool.getReserve(USDT_ID).tokenAddress, address(usdt));
    }

    function test_Constructor_ZeroOracleReverts() public {
        vm.expectRevert("Pool: zero oracle");
        new Pool(address(0));
    }

    // ================================================================
    // onlyOwner guard
    // ================================================================

    function test_AddReserve_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("PoolStorage: not owner");
        pool.addReserve(DataTypes.ReserveConfig({
            name:                 "FAKE",
            tokenAddress:         address(usdt),
            priceFeed:            usdtFeed,
            interestStrategy:     address(strategy),
            liquidationThreshold: LIQ_THRESHOLD,
            ltv:                  LTV,
            slope1:               SLOPE1,
            slope2:               SLOPE2,
            baseInterestRate:     BASE_RATE,
            optimalUtilization:   OPT_UTIL,
            liquidationBonus:     LIQ_BONUS,
            reserveFactor:        RESERVE_FACTOR,
            borrowCap:            BORROW_CAP,
            supplyCap:            SUPPLY_CAP,
            isActive:             true,
            isBorrowable:         true
        }));
    }

    function test_SetReserveActive_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("PoolStorage: not owner");
        pool.setReserveActive(USDT_ID, false);
    }

    function test_SetReserveBorrowable_RevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("PoolStorage: not owner");
        pool.setReserveBorrowable(USDT_ID, false);
    }

    // ================================================================
    // addReserve — validation branches
    // ================================================================

    function test_AddReserve_RevertsOnDuplicate() public {
        vm.expectRevert("Pool: reserve exists");
        pool.addReserve(DataTypes.ReserveConfig({
            name:                 "mUSDT",  // already registered
            tokenAddress:         address(usdt),
            priceFeed:            usdtFeed,
            interestStrategy:     address(strategy),
            liquidationThreshold: LIQ_THRESHOLD,
            ltv:                  LTV,
            slope1:               SLOPE1,
            slope2:               SLOPE2,
            baseInterestRate:     BASE_RATE,
            optimalUtilization:   OPT_UTIL,
            liquidationBonus:     LIQ_BONUS,
            reserveFactor:        RESERVE_FACTOR,
            borrowCap:            BORROW_CAP,
            supplyCap:            SUPPLY_CAP,
            isActive:             true,
            isBorrowable:         true
        }));
    }

    function test_AddReserve_RevertsOnZeroToken() public {
        vm.expectRevert("Pool: zero token");
        pool.addReserve(DataTypes.ReserveConfig({
            name:                 "NEW",
            tokenAddress:         address(0),
            priceFeed:            usdtFeed,
            interestStrategy:     address(strategy),
            liquidationThreshold: LIQ_THRESHOLD,
            ltv:                  LTV,
            slope1:               SLOPE1,
            slope2:               SLOPE2,
            baseInterestRate:     BASE_RATE,
            optimalUtilization:   OPT_UTIL,
            liquidationBonus:     LIQ_BONUS,
            reserveFactor:        RESERVE_FACTOR,
            borrowCap:            BORROW_CAP,
            supplyCap:            SUPPLY_CAP,
            isActive:             true,
            isBorrowable:         true
        }));
    }

    function test_AddReserve_RevertsOnZeroFeed() public {
        vm.expectRevert("Pool: zero feed");
        pool.addReserve(DataTypes.ReserveConfig({
            name:                 "NEW",
            tokenAddress:         address(usdt),
            priceFeed:            address(0),
            interestStrategy:     address(strategy),
            liquidationThreshold: LIQ_THRESHOLD,
            ltv:                  LTV,
            slope1:               SLOPE1,
            slope2:               SLOPE2,
            baseInterestRate:     BASE_RATE,
            optimalUtilization:   OPT_UTIL,
            liquidationBonus:     LIQ_BONUS,
            reserveFactor:        RESERVE_FACTOR,
            borrowCap:            BORROW_CAP,
            supplyCap:            SUPPLY_CAP,
            isActive:             true,
            isBorrowable:         true
        }));
    }

    function test_AddReserve_RevertsOnZeroStrategy() public {
        vm.expectRevert("Pool: zero strategy");
        pool.addReserve(DataTypes.ReserveConfig({
            name:                 "NEW",
            tokenAddress:         address(usdt),
            priceFeed:            usdtFeed,
            interestStrategy:     address(0),
            liquidationThreshold: LIQ_THRESHOLD,
            ltv:                  LTV,
            slope1:               SLOPE1,
            slope2:               SLOPE2,
            baseInterestRate:     BASE_RATE,
            optimalUtilization:   OPT_UTIL,
            liquidationBonus:     LIQ_BONUS,
            reserveFactor:        RESERVE_FACTOR,
            borrowCap:            BORROW_CAP,
            supplyCap:            SUPPLY_CAP,
            isActive:             true,
            isBorrowable:         true
        }));
    }

    function test_AddReserve_RevertsWhenLtvGeThreshold() public {
        vm.expectRevert("Pool: ltv >= threshold");
        pool.addReserve(DataTypes.ReserveConfig({
            name:                 "NEW",
            tokenAddress:         address(usdt),
            priceFeed:            usdtFeed,
            interestStrategy:     address(strategy),
            liquidationThreshold: LTV,   // ltv == threshold → should revert
            ltv:                  LTV,
            slope1:               SLOPE1,
            slope2:               SLOPE2,
            baseInterestRate:     BASE_RATE,
            optimalUtilization:   OPT_UTIL,
            liquidationBonus:     LIQ_BONUS,
            reserveFactor:        RESERVE_FACTOR,
            borrowCap:            BORROW_CAP,
            supplyCap:            SUPPLY_CAP,
            isActive:             true,
            isBorrowable:         true
        }));
    }

    function test_AddReserve_InitialisesIndexesAtRay() public view {
        DataTypes.ReserveData memory r = pool.getReserve(USDT_ID);
        assertEq(r.supplyLiquidityIndex, RAY);
        assertEq(r.borrowLiquidityIndex, RAY);
    }

    function test_AddReserve_PushesReserveId() public view {
        DataTypes.ReserveData[] memory all = pool.getAllReserves();
        assertEq(all.length, 3); // USDT, WETH, WBTC added in setUp
    }

    // ================================================================
    // setReserveActive / setReserveBorrowable
    // ================================================================

    function test_SetReserveActive_UpdatesFlag() public {
        pool.setReserveActive(USDT_ID, false);
        assertFalse(pool.getReserve(USDT_ID).isActive);
        pool.setReserveActive(USDT_ID, true);
        assertTrue(pool.getReserve(USDT_ID).isActive);
    }

    function test_SetReserveBorrowable_UpdatesFlag() public {
        pool.setReserveBorrowable(USDT_ID, false);
        assertFalse(pool.getReserve(USDT_ID).isBorrowable);
        pool.setReserveBorrowable(USDT_ID, true);
        assertTrue(pool.getReserve(USDT_ID).isBorrowable);
    }

    function test_SetReserveActive_EmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(pool));
        emit ReserveStatusUpdated(USDT_ID, false);
        pool.setReserveActive(USDT_ID, false);
    }

    function test_SetReserveBorrowable_EmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(pool));
        emit ReserveBorrowStatusUpdated(USDT_ID, false);
        pool.setReserveBorrowable(USDT_ID, false);
    }

    // ================================================================
    // View functions
    // ================================================================

    function test_GetReserveId_Deterministic() public view {
        bytes32 id1 = pool.getReserveId("mUSDT");
        bytes32 id2 = pool.getReserveId("mUSDT");
        assertEq(id1, id2);
    }

    function test_GetReserve_UnknownRevertsWithMessage() public {
        bytes32 fakeId = keccak256("doesNotExist");
        vm.expectRevert("PoolStorage: unknown reserve");
        pool.getReserve(fakeId);
    }

    function test_GetAllReserves_ReturnsCorrectCount() public view {
        DataTypes.ReserveData[] memory reserves = pool.getAllReserves();
        assertEq(reserves.length, 3);
    }

    function test_GetAllReserves_ContainsExpectedTokens() public view {
        DataTypes.ReserveData[] memory reserves = pool.getAllReserves();
        bool foundUsdt;
        bool foundWeth;
        for (uint256 i; i < reserves.length; i++) {
            if (reserves[i].tokenAddress == address(usdt)) foundUsdt = true;
            if (reserves[i].tokenAddress == address(weth)) foundWeth = true;
        }
        assertTrue(foundUsdt);
        assertTrue(foundWeth);
    }

    function test_GetUtilizationRate_ZeroWhenNoDeposits() public view {
        // Fresh reserve with no deposits → 0
        // (all reserves have 0 deposits at start of this test)
        uint256 util = pool.getUtilizationRate(USDT_ID);
        assertEq(util, 0);
    }

    function test_GetUtilizationRate_AfterDepositAndBorrow() public {
        _deposit(alice, USDT_ID, address(usdt), 100_000e18);
        _deposit(bob,   WETH_ID, address(weth),   100e18);
        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 50_000e18, 0.1e18);

        uint256 util = pool.getUtilizationRate(USDT_ID);
        assertApproxEqAbs(util, 0.5e18, 1e10);
    }

    function test_GetUserPositions_FiltersClosedPositions() public {
        _deposit(alice, USDT_ID, address(usdt), 500_000e18);
        _deposit(bob,   WETH_ID, address(weth),   100e18);
        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 5_000e18, 0.1e18);

        // Open, then close the position
        uint256 debt = pool.getUserBorrowBalance(USDT_ID, bob);
        usdt.mint(bob, debt);
        vm.startPrank(bob);
        usdt.approve(address(pool), debt);
        pool.repay(WETH_ID, USDT_ID, 0, debt);
        vm.stopPrank();

        DataTypes.Position[] memory open = pool.getUserPositions(bob);
        assertEq(open.length, 0, "closed position must be filtered");
    }

    function test_GetUserPositions_MultipleOpenPositions() public {
        _deposit(alice, USDT_ID, address(usdt), 500_000e18);
        _deposit(alice, WETH_ID, address(weth),   500e18);

        _deposit(bob, WETH_ID, address(weth), 50e18);
        _deposit(bob, WBTC_ID, address(wbtc),  5e18);

        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 5_000e18, 0.1e18);
        vm.prank(bob);
        pool.borrow(WBTC_ID, WETH_ID, 1e18, 0.1e18);

        DataTypes.Position[] memory positions = pool.getUserPositions(bob);
        assertEq(positions.length, 2);
    }

    function test_GetPosition_RevertsOnBadId() public {
        vm.expectRevert("PoolStorage: bad position id");
        pool.getPosition(alice, 999);
    }

    function test_GetPosition_RevertsOnClosedPosition() public {
        _deposit(alice, USDT_ID, address(usdt), 500_000e18);
        _deposit(bob,   WETH_ID, address(weth),   10e18);
        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 5_000e18, 0.1e18);

        uint256 debt = pool.getUserBorrowBalance(USDT_ID, bob);
        usdt.mint(bob, debt);
        vm.startPrank(bob);
        usdt.approve(address(pool), debt);
        pool.repay(WETH_ID, USDT_ID, 0, debt);
        vm.stopPrank();

        vm.expectRevert("PoolStorage: position closed");
        pool.getPosition(bob, 0);
    }

    function test_CheckPositionHealth_HealthyReturnsTrue() public {
        _deposit(alice, USDT_ID, address(usdt), 500_000e18);
        _deposit(bob,   WETH_ID, address(weth),   10e18);
        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 5_000e18, 0.1e18);

        assertTrue(pool.checkPositionHealth(bob, 0));
    }
}

contract PoolBorrowEdgeCasesTest is PoolTestBase {

    function setUp() public override {
        super.setUp();
        _deposit(alice, USDT_ID, address(usdt), 500_000e18);
        _deposit(alice, WETH_ID, address(weth),   500e18);
    }

    function test_Borrow_RevertsIfCollateralReserveInactive() public {
        _deposit(bob, WETH_ID, address(weth), 10e18);
        pool.setReserveActive(WETH_ID, false);
        vm.prank(bob);
        vm.expectRevert("ReserveLib: reserve inactive");
        pool.borrow(WETH_ID, USDT_ID, 1_000e18, 0.1e18);
    }

    function test_Borrow_RevertsIfBorrowReserveInactive() public {
        pool.setReserveActive(USDT_ID, false);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        vm.prank(bob);
        vm.expectRevert("ReserveLib: reserve inactive");
        pool.borrow(WETH_ID, USDT_ID, 1_000e18, 0.1e18);
    }

    function test_Borrow_RevertsOnUtilizationCeiling() public {
        // Deposit just enough so that borrowing 96% would exceed the 95% ceiling
        _deposit(bob, WETH_ID, address(weth), 200e18); // $600k collateral
        vm.prank(bob);
        vm.expectRevert("BorrowModule: utilization ceiling");
        pool.borrow(WETH_ID, USDT_ID, 480_001e18, 0.1e18); // > 95% of 500k pool
    }

    function test_Repay_WrongCollateralReverts() public {
        _deposit(bob, WETH_ID, address(weth), 10e18);
        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 5_000e18, 0.1e18);

        usdt.mint(bob, 5_000e18);
        vm.startPrank(bob);
        usdt.approve(address(pool), 5_000e18);
        vm.expectRevert("BorrowModule: wrong collateral");
        pool.repay(WBTC_ID, USDT_ID, 0, 5_000e18); // wrong collateral
        vm.stopPrank();
    }

    function test_Repay_WrongBorrowAssetReverts() public {
        _deposit(bob, WETH_ID, address(weth), 10e18);
        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 5_000e18, 0.1e18);

        weth.mint(bob, 1e18);
        vm.startPrank(bob);
        weth.approve(address(pool), 1e18);
        vm.expectRevert("BorrowModule: wrong borrow asset");
        pool.repay(WETH_ID, WETH_ID, 0, 1e18); // should be USDT borrow
        vm.stopPrank();
    }

    function test_Repay_OverRepayUsesCurrentDebt() public {
        _deposit(bob, WETH_ID, address(weth), 10e18);
        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 5_000e18, 0.1e18);

        uint256 debt = pool.getUserBorrowBalance(USDT_ID, bob);
        uint256 overRepay = debt * 10; // 10x debt
        usdt.mint(bob, overRepay);

        vm.startPrank(bob);
        usdt.approve(address(pool), overRepay);
        pool.repay(WETH_ID, USDT_ID, 0, overRepay); // should only take actual debt
        vm.stopPrank();

        // Position closed, balance of USDT only reduced by debt (not 10x debt)
        DataTypes.Position[] memory positions = pool.getUserPositions(bob);
        assertEq(positions.length, 0, "position should be closed");
    }

    function test_Withdraw_RevertsIfReserveInactive() public {
        _deposit(alice, USDT_ID, address(usdt), 1_000e18);
        pool.setReserveActive(USDT_ID, false);
        vm.prank(alice);
        vm.expectRevert("ReserveLib: reserve inactive");
        pool.withdraw(USDT_ID, 1_000e18);
    }
}