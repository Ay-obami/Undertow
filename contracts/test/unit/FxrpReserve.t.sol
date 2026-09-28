// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Pool} from "../../src/modules/Pool.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {VariableInterestStrategy} from "../../src/modules/VariableInterestStrategy.sol";
import {FtsoOracle} from "../../src/oracle/FtsoOracle.sol";
import {MockFtsoV2} from "../mocks/MockFtsoV2.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice End-to-end test proving FXRP works as a first-class collateral/borrow
///         reserve priced entirely off FTSOv2 (via FtsoOracle) — the "Support
///         FXRP as a first-class collateral and borrow asset" goal from the PRD.
///
///         Real FXRP/WFLR addresses only exist on Coston2 (see
///         scripts/DeployCoston2.s.sol); here MockERC20 stands in for both
///         tokens so the reserve mechanics can be exercised without a fork.
contract FxrpReserveTest is Test {
    address internal constant REGISTRY = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant XRP_USD_ID = bytes21(0x015852502f55534400000000000000000000000000);
    bytes21 internal constant FLR_USD_ID = bytes21(0x01464c522f55534400000000000000000000000000);

    Pool internal pool;
    FtsoOracle internal oracle;
    MockFtsoV2 internal mockFtso;
    VariableInterestStrategy internal strategy;

    MockERC20 internal fxrp; // stand-in for the real FXRP FAsset
    MockERC20 internal wflr; // stand-in for wrapped native FLR

    bytes32 internal FXRP_ID;
    bytes32 internal WFLR_ID;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 constant RAY = 1e18;

    function setUp() public {
        strategy = new VariableInterestStrategy();
        oracle = new FtsoOracle(300, address(this));
        mockFtso = new MockFtsoV2();

        vm.mockCall(
            REGISTRY,
            abi.encodeWithSignature("getContractAddressByHash(bytes32)", keccak256(abi.encode("FtsoV2"))),
            abi.encode(address(mockFtso))
        );

        fxrp = new MockERC20("FXRP", "FXRP");
        wflr = new MockERC20("Wrapped FLR", "WFLR");

        oracle.setFeedId(address(fxrp), XRP_USD_ID);
        oracle.setFeedId(address(wflr), FLR_USD_ID);

        // XRP/USD = $3.15, FLR/USD = $0.03 (5-decimal FTSOv2 mantissas)
        mockFtso.setFeed(XRP_USD_ID, 315_000, 5, uint64(block.timestamp));
        mockFtso.setFeed(FLR_USD_ID, 3_000, 5, uint64(block.timestamp));

        pool = new Pool(address(oracle));

        pool.addReserve(
            DataTypes.ReserveConfig({
                name: "FXRP",
                tokenAddress: address(fxrp),
                priceFeed: address(fxrp),
                interestStrategy: address(strategy),
                liquidationThreshold: 80 * RAY / 100,
                ltv: 75 * RAY / 100,
                slope1: 5 * RAY / 100,
                slope2: 75 * RAY / 100,
                baseInterestRate: 1 * RAY / 100,
                optimalUtilization: 75 * RAY / 100,
                liquidationBonus: 8 * RAY / 100,
                reserveFactor: 15 * RAY / 100,
                borrowCap: 1_000_000e18,
                supplyCap: 1_000_000e18,
                isActive: true,
                isBorrowable: true
            })
        );

        pool.addReserve(
            DataTypes.ReserveConfig({
                name: "WFLR",
                tokenAddress: address(wflr),
                priceFeed: address(wflr),
                interestStrategy: address(strategy),
                liquidationThreshold: 70 * RAY / 100,
                ltv: 65 * RAY / 100,
                slope1: 6 * RAY / 100,
                slope2: 90 * RAY / 100,
                baseInterestRate: 2 * RAY / 100,
                optimalUtilization: 70 * RAY / 100,
                liquidationBonus: 10 * RAY / 100,
                reserveFactor: 20 * RAY / 100,
                borrowCap: 50_000_000e18,
                supplyCap: 50_000_000e18,
                isActive: true,
                isBorrowable: true
            })
        );

        FXRP_ID = pool.getReserveId("FXRP");
        WFLR_ID = pool.getReserveId("WFLR");

        fxrp.mint(alice, 10_000e18);
        wflr.mint(bob, 10_000_000e18);
    }

    // ── Deposit ──────────────────────────────────────────────────────

    function test_DepositFxrp_AsCollateral() public {
        vm.startPrank(alice);
        fxrp.approve(address(pool), 1_000e18);
        pool.deposit(FXRP_ID, 1_000e18);
        vm.stopPrank();

        assertEq(fxrp.balanceOf(address(pool)), 1_000e18);
    }

    // ── Borrow against FXRP collateral ──────────────────────────────

    function test_BorrowWflr_AgainstFxrpCollateral() public {
        // Bob seeds WFLR liquidity for Alice to borrow against.
        vm.startPrank(bob);
        wflr.approve(address(pool), 5_000_000e18);
        pool.deposit(WFLR_ID, 5_000_000e18);
        vm.stopPrank();

        // Alice deposits 1,000 FXRP (~$3,150) as collateral, buffer 20%.
        vm.startPrank(alice);
        fxrp.approve(address(pool), 1_000e18);
        pool.deposit(FXRP_ID, 1_000e18);

        // Borrows 50,000 WFLR (~$1,500) — comfortably within the 75% LTV.
        pool.borrow(FXRP_ID, WFLR_ID, 50_000e18, 20 * RAY / 100);
        vm.stopPrank();

        assertEq(wflr.balanceOf(alice), 50_000e18);
    }

    function test_Borrow_RevertsIfExceedsLtv() public {
        vm.startPrank(bob);
        wflr.approve(address(pool), 5_000_000e18);
        pool.deposit(WFLR_ID, 5_000_000e18);
        vm.stopPrank();

        vm.startPrank(alice);
        fxrp.approve(address(pool), 1_000e18);
        pool.deposit(FXRP_ID, 1_000e18);

        // 1,000 FXRP ≈ $3,150 collateral; borrowing 200,000 WFLR ≈ $6,000
        // is well past the 75% LTV and must revert.
        vm.expectRevert();
        pool.borrow(FXRP_ID, WFLR_ID, 200_000e18, 20 * RAY / 100);
        vm.stopPrank();
    }

    // ── Price-driven liquidation ─────────────────────────────────────

    function test_Liquidation_TriggeredByXrpPriceDrop() public {
        vm.startPrank(bob);
        wflr.approve(address(pool), 5_000_000e18);
        pool.deposit(WFLR_ID, 5_000_000e18);
        vm.stopPrank();

        vm.startPrank(alice);
        fxrp.approve(address(pool), 1_000e18);
        pool.deposit(FXRP_ID, 1_000e18);
        pool.borrow(FXRP_ID, WFLR_ID, 60_000e18, 5 * RAY / 100); // near max LTV
        vm.stopPrank();

        assertTrue(pool.checkPositionHealth(alice, 0), "position should start healthy");

        // XRP/USD crashes from $3.15 to $1.50 — position becomes unhealthy.
        mockFtso.setFeed(XRP_USD_ID, 150_000, 5, uint64(block.timestamp));

        assertFalse(pool.checkPositionHealth(alice, 0), "position should be unhealthy after price crash");

        // Bob repays Alice's full debt and seizes discounted FXRP collateral
        // (plus the liquidation bonus) in a single call.
        vm.startPrank(bob);
        wflr.approve(address(pool), 60_000e18);
        pool.liquidate(alice, 0);
        vm.stopPrank();

        assertGt(fxrp.balanceOf(bob), 0, "liquidator should receive seized FXRP");
    }
}
