// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolTestBase} from "./PoolTestBase.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

contract LendingViewReadsTest is PoolTestBase {
    function setUp() public override {
        super.setUp();
        _deposit(alice, USDT_ID, address(usdt), 22_000e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, USDT_ID, 20_000e18, 0.05e18);
    }

    function _staticBalance(bytes4 selector, address user) internal view returns (uint256) {
        (bool ok, bytes memory result) = address(pool).staticcall(abi.encodeWithSelector(selector, USDT_ID, user));
        require(ok, "balance read reverted under staticcall");
        return abi.decode(result, (uint256));
    }

    function test_BorrowBalanceStaticcallAccruesWithoutTouchingReserve() public {
        DataTypes.ReserveData memory beforeRead = pool.getReserve(USDT_ID);
        vm.warp(block.timestamp + 180 days);
        uint256 debt = _staticBalance(pool.getUserBorrowBalance.selector, bob);
        assertGt(debt, 20_000e18);
        assertEq(keccak256(abi.encode(pool.getReserve(USDT_ID))), keccak256(abi.encode(beforeRead)));
    }

    function test_DepositBalanceStaticcallAccruesWithoutTouchingReserve() public {
        DataTypes.ReserveData memory beforeRead = pool.getReserve(USDT_ID);
        vm.warp(block.timestamp + 180 days);
        uint256 deposit = _staticBalance(pool.getUserDepositBalance.selector, alice);
        assertGt(deposit, 22_000e18);
        assertEq(keccak256(abi.encode(pool.getReserve(USDT_ID))), keccak256(abi.encode(beforeRead)));
    }

    function test_DirectBalanceReadsDoNotMutateReserve() public {
        DataTypes.ReserveData memory beforeRead = pool.getReserve(USDT_ID);
        vm.warp(block.timestamp + 180 days);
        assertGt(pool.getUserBorrowBalance(USDT_ID, bob), 20_000e18);
        assertGt(pool.getUserDepositBalance(USDT_ID, alice), 22_000e18);
        assertEq(keccak256(abi.encode(pool.getReserve(USDT_ID))), keccak256(abi.encode(beforeRead)));
    }

    function testFuzz_ReadPreviewMatchesNextIndexUpdate(uint32 rawElapsed) public {
        uint256 elapsed = bound(uint256(rawElapsed), 1, 365 days);
        vm.warp(block.timestamp + elapsed);
        uint256 debt = _staticBalance(pool.getUserBorrowBalance.selector, bob);
        uint256 deposit = _staticBalance(pool.getUserDepositBalance.selector, alice);
        _deposit(alice, USDT_ID, address(usdt), 1e18);
        assertEq(pool.getUserBorrowBalance(USDT_ID, bob), debt);
        assertApproxEqAbs(pool.getUserDepositBalance(USDT_ID, alice), deposit + 1e18, 2);
    }

    function test_BalancesAtSameTimestampAreUnchanged() public {
        assertEq(_staticBalance(pool.getUserBorrowBalance.selector, bob), 20_000e18);
        assertEq(_staticBalance(pool.getUserDepositBalance.selector, alice), 22_000e18);
    }

    function test_HealthCheckReflectsAccruedBorrowDebtWithoutReserveTouch() public {
        assertTrue(pool.checkPositionHealth(bob, 0));
        vm.warp(block.timestamp + 365 days);
        assertFalse(pool.checkPositionHealth(bob, 0));
    }
}
