// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolTestBase} from "./PoolTestBase.sol";

contract SupplyModuleTest is PoolTestBase {

    event Deposit(address indexed user, bytes32 indexed reserveId, uint256 amount, uint256 scaledAmount);
    // ================================================================
    // deposit
    // ================================================================

    function test_Deposit_UpdatesTotalDeposits() public {
        _deposit(alice, USDT_ID, address(usdt), 1_000e18);
        assertEq(pool.getReserve(USDT_ID).totalDeposits, 1_000e18);
    }

    function test_Deposit_UserBalanceAccurate() public {
        _deposit(alice, USDT_ID, address(usdt), 1_000e18);
        assertEq(pool.getUserDepositBalance(USDT_ID, alice), 1_000e18);
    }

    function test_Deposit_MultipleUsers() public {
        _deposit(alice, USDT_ID, address(usdt), 1_000e18);
        _deposit(bob,   USDT_ID, address(usdt), 2_000e18);

        assertEq(pool.getReserve(USDT_ID).totalDeposits, 3_000e18);
        assertEq(pool.getUserDepositBalance(USDT_ID, alice), 1_000e18);
        assertEq(pool.getUserDepositBalance(USDT_ID, bob),   2_000e18);
    }

    function test_Deposit_EmitsEvent() public {
        vm.startPrank(alice);
        usdt.approve(address(pool), 500e18);
        vm.expectEmit(true, true, false, false, address(pool));
        emit Deposit(alice, USDT_ID, 500e18, 500e18); // scaled = real when index = 1
        pool.deposit(USDT_ID, 500e18);
        vm.stopPrank();
    }

    function test_Deposit_RevertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("SupplyModule: zero amount");
        pool.deposit(USDT_ID, 0);
    }

    function test_Deposit_RevertsWhenInactive() public {
        pool.setReserveActive(USDT_ID, false);

        vm.startPrank(alice);
        usdt.approve(address(pool), 1_000e18);
        vm.expectRevert("ReserveLib: reserve inactive");
        pool.deposit(USDT_ID, 1_000e18);
        vm.stopPrank();
    }

    function test_Deposit_RevertsWhenSupplyCapExceeded() public {
        // supplyCap = 1_000_000e18, try to deposit more
        uint256 overCap = 1_000_001e18;
        usdt.mint(alice, overCap);

        vm.startPrank(alice);
        usdt.approve(address(pool), overCap);
        vm.expectRevert("ReserveLib: supply cap exceeded");
        pool.deposit(USDT_ID, overCap);
        vm.stopPrank();
    }

    function test_Deposit_CapCheckUsesCurrentDeposits() public {
        // Deposit up to the cap, then try one more — must revert
        _deposit(alice, USDT_ID, address(usdt), 1_000_000e18);

        usdt.mint(bob, 1e18);
        vm.startPrank(bob);
        usdt.approve(address(pool), 1e18);
        vm.expectRevert("ReserveLib: supply cap exceeded");
        pool.deposit(USDT_ID, 1e18);
        vm.stopPrank();
    }

    // ================================================================
    // withdraw
    // ================================================================

    function test_Withdraw_PartialAmount() public {
        _deposit(alice, USDT_ID, address(usdt), 1_000e18);
        vm.prank(alice);
        pool.withdraw(USDT_ID, 400e18);

        assertEq(pool.getReserve(USDT_ID).totalDeposits, 600e18);
        assertApproxEqAbs(pool.getUserDepositBalance(USDT_ID, alice), 600e18, 1);
    }

    function test_Withdraw_FullAmount() public {
        _deposit(alice, USDT_ID, address(usdt), 1_000e18);
        vm.prank(alice);
        pool.withdraw(USDT_ID, 1_000e18);

        assertEq(pool.getReserve(USDT_ID).totalDeposits, 0);
        assertEq(pool.getUserDepositBalance(USDT_ID, alice), 0);
    }

    function test_Withdraw_TransfersTokens() public {
        _deposit(alice, USDT_ID, address(usdt), 1_000e18);
        uint256 before = usdt.balanceOf(alice);
        vm.prank(alice);
        pool.withdraw(USDT_ID, 1_000e18);
        assertEq(usdt.balanceOf(alice) - before, 1_000e18);
    }

    function test_Withdraw_RevertsIfInsufficientBalance() public {
        _deposit(alice, USDT_ID, address(usdt), 500e18);
        vm.prank(alice);
        vm.expectRevert("SupplyModule: insufficient balance");
        pool.withdraw(USDT_ID, 1_000e18);
    }

    function test_Withdraw_RevertsOnZeroAmount() public {
        _deposit(alice, USDT_ID, address(usdt), 1_000e18);
        vm.prank(alice);
        vm.expectRevert("SupplyModule: zero amount");
        pool.withdraw(USDT_ID, 0);
    }

    function test_Withdraw_InterestAccruesOverTime() public {
        // Seed deposits and a borrow to generate non-zero utilization
        _deposit(alice, USDT_ID, address(usdt), 100_000e18);
        _deposit(bob,   WETH_ID, address(weth), 100e18);

        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 50_000e18, 0.1e18);

        // Fast-forward 1 year
        vm.warp(block.timestamp + 365 days);

        // Alice should now be able to withdraw slightly more than she deposited
        uint256 balance = pool.getUserDepositBalance(USDT_ID, alice);
        assertGt(balance, 100_000e18);
    }
}
