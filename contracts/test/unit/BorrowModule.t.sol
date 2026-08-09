// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolTestBase} from "./PoolTestBase.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

contract BorrowModuleTest is PoolTestBase {
    function setUp() public override {
        super.setUp();
        // Seed base liquidity so borrows have pool funds to draw from
        _deposit(alice, USDT_ID, address(usdt), 500_000e18);
        _deposit(alice, WETH_ID, address(weth), 500e18);
        _deposit(alice, WBTC_ID, address(wbtc), 50e18);
    }

    // ================================================================
    // borrow
    // ================================================================

    function test_Borrow_TotalBorrowsIncreases() public {
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, USDT_ID, 10_000e18, 0.1e18);

        assertEq(pool.getReserve(USDT_ID).totalBorrows, 10_000e18);
    }

    function test_Borrow_TransfersBorrowedTokenToUser() public {
        _deposit(bob, WETH_ID, address(weth), 10e18);
        uint256 before = usdt.balanceOf(bob);
        _borrow(bob, WETH_ID, USDT_ID, 5_000e18, 0.1e18);
        assertEq(usdt.balanceOf(bob) - before, 5_000e18);
    }

    function test_Borrow_LocksCollateralFromDeposit() public {
        _deposit(bob, WETH_ID, address(weth), 10e18);
        uint256 depositBefore = pool.getUserDepositBalance(WETH_ID, bob);
        _borrow(bob, WETH_ID, USDT_ID, 5_000e18, 0.1e18);
        uint256 depositAfter  = pool.getUserDepositBalance(WETH_ID, bob);
        assertLt(depositAfter, depositBefore);
    }

    function test_Borrow_CreatesPosition() public {
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, USDT_ID, 5_000e18, 0.1e18);

        DataTypes.Position[] memory positions = pool.getUserPositions(bob);
        assertEq(positions.length, 1);
        assertEq(positions[0].borrowReserveId,    USDT_ID);
        assertEq(positions[0].collateralReserveId, WETH_ID);
        assertTrue(positions[0].isOpen);
    }

    function test_Borrow_RevertsOnZeroAmount() public {
        _deposit(bob, WETH_ID, address(weth), 10e18);
        vm.prank(bob);
        vm.expectRevert("BorrowModule: zero amount");
        pool.borrow(WETH_ID, USDT_ID, 0, 0.1e18);
    }

    function test_Borrow_RevertsOnSameAsset() public {
        _deposit(bob, USDT_ID, address(usdt), 10_000e18);
        vm.prank(bob);
        vm.expectRevert("BorrowModule: same asset");
        pool.borrow(USDT_ID, USDT_ID, 1_000e18, 0.1e18);
    }

    function test_Borrow_RevertsIfBufferTooLow() public {
        _deposit(bob, WETH_ID, address(weth), 10e18);
        vm.prank(bob);
        vm.expectRevert("BorrowModule: buffer out of range");
        pool.borrow(WETH_ID, USDT_ID, 1_000e18, 0.01e18);
    }

    function test_Borrow_RevertsIfBufferTooHigh() public {
        _deposit(bob, WETH_ID, address(weth), 10e18);
        vm.prank(bob);
        vm.expectRevert("BorrowModule: buffer out of range");
        pool.borrow(WETH_ID, USDT_ID, 1_000e18, 1.1e18);
    }

    function test_Borrow_RevertsIfNotBorrowable() public {
        pool.setReserveBorrowable(USDT_ID, false);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        vm.prank(bob);
        vm.expectRevert("ReserveLib: reserve not borrowable");
        pool.borrow(WETH_ID, USDT_ID, 1_000e18, 0.1e18);
    }

    function test_Borrow_RevertsIfInsufficientCollateral() public {
        _deposit(bob, WETH_ID, address(weth), 1e18); // ~$3000 worth
        vm.prank(bob);
        vm.expectRevert("BorrowModule: insufficient collateral");
        pool.borrow(WETH_ID, USDT_ID, 100_000e18, 0.1e18); // wants $100k
    }

    function test_Borrow_RevertsIfBorrowCapExceeded() public {
        _deposit(bob, WETH_ID, address(weth), 1000e18);
        vm.prank(bob);
        vm.expectRevert("ReserveLib: borrow cap exceeded");
        pool.borrow(WETH_ID, USDT_ID, BORROW_CAP + 1, 0.1e18);
    }

    // ================================================================
    // repay
    // ================================================================

    function _openPosition() internal returns (uint256 positionId) {
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, USDT_ID, 5_000e18, 0.1e18);
        positionId = 0;
    }

    function test_Repay_FullRepayClosesPosition() public {
        _openPosition();
        uint256 debt = pool.getUserBorrowBalance(USDT_ID, bob);

        // Give bob extra usdt to cover accrued interest
        usdt.mint(bob, debt);
        vm.startPrank(bob);
        usdt.approve(address(pool), debt);
        pool.repay(WETH_ID, USDT_ID, 0, debt);
        vm.stopPrank();

        DataTypes.Position[] memory positions = pool.getUserPositions(bob);
        assertEq(positions.length, 0); // closed position filtered out
    }

    function test_Repay_ReducesTotalBorrows() public {
        _openPosition();
        uint256 before = pool.getReserve(USDT_ID).totalBorrows;

        usdt.mint(bob, 2_000e18);
        vm.startPrank(bob);
        usdt.approve(address(pool), 2_000e18);
        pool.repay(WETH_ID, USDT_ID, 0, 2_000e18);
        vm.stopPrank();

        assertLt(pool.getReserve(USDT_ID).totalBorrows, before);
    }

    function test_Repay_ReleasesCollateralProportionally() public {
        _openPosition();
        uint256 collateralBefore = pool.getUserDepositBalance(WETH_ID, bob);

        usdt.mint(bob, 2_500e18);
        vm.startPrank(bob);
        usdt.approve(address(pool), 2_500e18);
        pool.repay(WETH_ID, USDT_ID, 0, 2_500e18); // ~50 % repay
        vm.stopPrank();

        uint256 collateralAfter = pool.getUserDepositBalance(WETH_ID, bob);
        assertGt(collateralAfter, collateralBefore);
    }

    function test_Repay_RevertsOnClosedPosition() public {
        _openPosition();
        uint256 debt = pool.getUserBorrowBalance(USDT_ID, bob);
        usdt.mint(bob, debt);

        vm.startPrank(bob);
        usdt.approve(address(pool), debt);
        pool.repay(WETH_ID, USDT_ID, 0, debt);
        // second repay on same (now closed) position
        vm.expectRevert("PoolStorage: position closed");
        pool.repay(WETH_ID, USDT_ID, 0, 1);
        vm.stopPrank();
    }

    // ================================================================
    // getUserBorrowBalance — pure view (bug-fix regression)
    // ================================================================

    function test_GetUserBorrowBalance_IsView() public {
        // Call from a staticcall context — if it mutates state this would revert
        _openPosition();
        bytes memory callData = abi.encodeWithSelector(
            pool.getUserBorrowBalance.selector, USDT_ID, bob
        );
        (bool ok,) = address(pool).staticcall(callData);
        assertTrue(ok, "getUserBorrowBalance must be a pure view");
    }
}
