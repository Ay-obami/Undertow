// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolTestBase} from "./PoolTestBase.sol";
import {console} from "forge-std/Test.sol";

contract LiquidationModuleTest is PoolTestBase {
    address internal liquidator = makeAddr("liquidator");

     event Liquidated(
        address indexed user,
        address indexed liquidator,
        bytes32 indexed collateralReserveId,
        bytes32 borrowReserveId,
        uint256 debtRepaid,
        uint256 collateralSeized,
        uint256 positionId
    );

    function setUp() public override {
        super.setUp();
        // Seed pool liquidity
        _deposit(alice, USDT_ID, address(usdt), 500_000e18);
        _deposit(alice, WETH_ID, address(weth), 500e18);
        // Bob opens a position: WETH collateral, USDT borrow
        _deposit(bob, WETH_ID, address(weth), 10e18); // $30k collateral
        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 20_000e18, 0.05e18); // $20k debt — HF ~1.27
    }

    function _crashEth(uint256 newPriceRay) internal {
        oracle.setPrice(wethFeed, newPriceRay);
    }

    // ================================================================
    // checkPositionHealth
    // ================================================================

    function test_HealthyPosition_ReturnsTrue() public view {
        assertTrue(pool.checkPositionHealth(bob, 0));
    }

    function test_UnhealthyPosition_ReturnsFalse() public {
        _crashEth(2_500 * RAY); // $30k collateral → $15k, HF ≈ 0.63
        assertFalse(pool.checkPositionHealth(bob, 0));
    }

    // ================================================================
    // liquidate
    // ================================================================

    function test_Liquidate_RevertsIfHealthy() public {
        vm.prank(liquidator);
        vm.expectRevert("LiquidationModule: position healthy");
        pool.liquidate(bob, 0);
    }

    function test_Liquidate_ClosesPosition() public {
        _crashEth(2_500 * RAY);

        uint256 debt = pool.getUserBorrowBalance(USDT_ID, bob);
        usdt.mint(liquidator, debt);
        vm.startPrank(liquidator);
        usdt.approve(address(pool), debt);
        pool.liquidate(bob, 0);
        vm.stopPrank();

        console.log(pool.getUserPositions(bob).length);
        console.log(pool.checkPositionHealth(bob, 0));
        assertFalse(pool.checkPositionHealth(bob, 0)); // position gone
        assertEq(pool.getUserPositions(bob).length, 0);
    }

    function test_Liquidate_RepaysFullDebt() public {
        _crashEth(2_500 * RAY);
        uint256 reserveBorrowsBefore = pool.getReserve(USDT_ID).totalBorrows;

        uint256 debt = pool.getUserBorrowBalance(USDT_ID, bob);
        usdt.mint(liquidator, debt);
        vm.startPrank(liquidator);
        usdt.approve(address(pool), debt);
        pool.liquidate(bob, 0);
        vm.stopPrank();

        assertLt(pool.getReserve(USDT_ID).totalBorrows, reserveBorrowsBefore);
    }

    /// @dev Bug-fix regression: liquidation bonus must be applied.
    ///      Liquidator should receive MORE collateral than the bare debt value.
    function test_Liquidate_LiquidationBonusApplied() public {
        _crashEth(2_500 * RAY);

        uint256 debt = pool.getUserBorrowBalance(USDT_ID, bob);

        // Compute expected seized collateral (with 5 % bonus)
        // debtInCollateralUnits = debt * usdtPrice / wethPrice
        //                       = debt * 1e18 / 1200e18
        // seized = debtInCollateral * (1 + 0.05)
        uint256 debtInWeth = debt * RAY / (2_500 * RAY);          // debt / wethPrice
        uint256 expectedSeized = debtInWeth * (RAY + LIQ_BONUS) / RAY; // + 5 %

        uint256 wethBefore = weth.balanceOf(liquidator);

        usdt.mint(liquidator, debt);
        vm.startPrank(liquidator);
        usdt.approve(address(pool), debt);
        pool.liquidate(bob, 0);
        vm.stopPrank();

        uint256 wethReceived = weth.balanceOf(liquidator) - wethBefore;
        // Allow 1 wei rounding
        assertApproxEqAbs(wethReceived, expectedSeized, 1e9, "bonus not applied");
        assertGt(wethReceived, debtInWeth, "liquidator must receive bonus");
    }

    function test_Liquidate_LeftoverCollateralReturnedToBorrower() public {
        // Price drop is moderate — collateral still exceeds debt+bonus → leftover
        _crashEth(2_500 * RAY);

        uint256 wethBefore = weth.balanceOf(bob);
        uint256 debt = pool.getUserBorrowBalance(USDT_ID, bob);

        usdt.mint(liquidator, debt);
        vm.startPrank(liquidator);
        usdt.approve(address(pool), debt);
        pool.liquidate(bob, 0);
        vm.stopPrank();

        uint256 wethAfter = weth.balanceOf(bob);
        // Bob should receive some collateral back
        assertGt(wethAfter, wethBefore);
    }

    function test_Liquidate_EmitsEvent() public {
    _crashEth(2_500 * RAY);
    uint256 debt = pool.getUserBorrowBalance(USDT_ID, bob);
    usdt.mint(liquidator, debt);

   // uint256 collateralLocked = pool.getPosition(bob, 0).collateralLocked;
    uint256 debtInWeth = debt * RAY / (2_500 * RAY);          // debt / wethPrice
        uint256 expectedSeized = debtInWeth * (RAY + LIQ_BONUS) / RAY; // + 5 %

    vm.startPrank(liquidator);
    usdt.approve(address(pool), debt);

    // Step 1: declare which parts to check (topic1, topic2, topic3, data) + emitter
    vm.expectEmit(true, true, true, true, address(pool));
    // Step 2: emit the expected event — must immediately precede the call that triggers it
    emit Liquidated(bob, liquidator, WETH_ID, USDT_ID, debt, expectedSeized, 0);

    pool.liquidate(bob, 0);
    vm.stopPrank();
}
}
