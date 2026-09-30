// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Pool} from "../../src/modules/Pool.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {MathLib} from "../../src/libraries/MathLib.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NativePrecisionToken is ERC20 {
    uint8 internal immutable precision;

    constructor(uint8 precision_) ERC20("Native token", "NATIVE") {
        precision = precision_;
    }

    function decimals() public view override returns (uint8) {
        return precision;
    }

    function mint(address user, uint256 amount) external {
        _mint(user, amount);
    }
}

contract FinalAuditRegressionsTest is PoolTestBase {
    function _config(string memory name, address token) internal view returns (DataTypes.ReserveConfig memory) {
        return DataTypes.ReserveConfig(
            name,
            token,
            usdtFeed,
            address(strategy),
            LIQ_THRESHOLD,
            LTV,
            SLOPE1,
            SLOPE2,
            BASE_RATE,
            OPT_UTIL,
            LIQ_BONUS,
            RESERVE_FACTOR,
            1_000_000e18,
            1_000_000e18,
            true,
            true
        );
    }

    function _nativeReserve(uint8 precision) internal returns (NativePrecisionToken token, bytes32 id) {
        token = new NativePrecisionToken(precision);
        pool.addReserve(_config("NATIVE", address(token)));
        id = pool.getReserveId("NATIVE");
        token.mint(alice, 100_000 * 10 ** precision);
        token.mint(bob, 100_000 * 10 ** precision);
        vm.prank(alice);
        token.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        token.approve(address(pool), type(uint256).max);
    }

    function test_SixDecimalDebtLocksCorrectCollateral() public {
        (, bytes32 id) = _nativeReserve(6);
        vm.prank(alice);
        pool.deposit(id, 10_000e6);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, id, 1_000e6, 0.05e18);
        assertEq(pool.getPosition(bob, 0).collateralLocked, 0.4375e18);
        assertTrue(pool.checkPositionHealth(bob, 0));
    }

    function test_SixDecimalCollateralSupportsBorrowAndRepay() public {
        (, bytes32 id) = _nativeReserve(6);
        _deposit(alice, WETH_ID, address(weth), 10e18);
        vm.prank(bob);
        pool.deposit(id, 10_000e6);
        _borrow(bob, id, WETH_ID, 1e18, 0.05e18);
        assertEq(pool.getPosition(bob, 0).collateralLocked, 3_937.5e6);
        vm.startPrank(bob);
        weth.approve(address(pool), type(uint256).max);
        pool.repay(id, WETH_ID, 0, type(uint256).max);
        vm.stopPrank();
        assertEq(pool.getUserDepositBalance(id, bob), 10_000e6);
    }

    function test_MixedDecimalLiquidationSeizesNativeUnits() public {
        (NativePrecisionToken token, bytes32 id) = _nativeReserve(6);
        vm.prank(alice);
        pool.deposit(id, 10_000e6);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, id, 1_000e6, 0.05e18);
        oracle.setPrice(wethFeed, 2_500e18);
        uint256 beforeTokens = weth.balanceOf(alice);
        uint256 beforePayment = token.balanceOf(alice);
        vm.prank(alice);
        pool.liquidate(bob, 0);
        assertEq(weth.balanceOf(alice) - beforeTokens, 0.42e18);
        assertEq(beforePayment - token.balanceOf(alice), 1_000e6);
    }

    function test_StableOpenPositionIdsSurviveClosedSlots() public {
        _deposit(alice, USDT_ID, address(usdt), 100_000e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, USDT_ID, 5_000e18, 0.05e18);
        _borrow(bob, WETH_ID, USDT_ID, 5_000e18, 0.05e18);
        vm.startPrank(bob);
        usdt.approve(address(pool), type(uint256).max);
        pool.repay(WETH_ID, USDT_ID, 0, type(uint256).max);
        vm.stopPrank();
        (bool ok, bytes memory data) =
            address(pool).staticcall(abi.encodeWithSignature("getUserPositionIds(address)", bob));
        assertTrue(ok, "stable ID getter missing");
        uint256[] memory ids = abi.decode(data, (uint256[]));
        assertEq(ids.length, 1);
        assertEq(ids[0], 1);
    }

    function test_TokenDecimalsGetterReportsNativePrecision() public {
        (, bytes32 id) = _nativeReserve(6);
        (bool ok, bytes memory data) =
            address(pool).staticcall(abi.encodeWithSignature("getReserveTokenDecimals(bytes32)", id));
        assertTrue(ok, "token decimals getter missing");
        assertEq(abi.decode(data, (uint8)), 6);
    }

    function test_RejectsInvalidRiskParameters() public {
        NativePrecisionToken token = new NativePrecisionToken(18);
        DataTypes.ReserveConfig memory cfg = _config("NEW", address(token));
        cfg.reserveFactor = 1e18 + 1;
        vm.expectRevert("Pool: invalid reserve factor");
        pool.addReserve(cfg);
        cfg.reserveFactor = RESERVE_FACTOR;
        cfg.optimalUtilization = 0;
        vm.expectRevert("Pool: invalid optimal utilization");
        pool.addReserve(cfg);
        cfg.optimalUtilization = 1e18;
        vm.expectRevert("Pool: invalid optimal utilization");
        pool.addReserve(cfg);
        cfg.optimalUtilization = OPT_UTIL;
        cfg.ltv = 0;
        vm.expectRevert("Pool: invalid ltv");
        pool.addReserve(cfg);
        cfg.ltv = LTV;
        cfg.liquidationThreshold = 1e18 + 1;
        vm.expectRevert("Pool: invalid liquidation threshold");
        pool.addReserve(cfg);
        cfg.liquidationThreshold = LIQ_THRESHOLD;
        cfg.liquidationBonus = 1e18 + 1;
        vm.expectRevert("Pool: invalid liquidation bonus");
        pool.addReserve(cfg);
        cfg.liquidationBonus = LIQ_BONUS;
        cfg.slope1 = 1e18 + 1;
        vm.expectRevert("Pool: invalid rate");
        pool.addReserve(cfg);
    }

    function test_RejectsDuplicateUnderlyingAsset() public {
        vm.expectRevert("Pool: token already listed");
        pool.addReserve(_config("ALIAS", address(usdt)));
    }

    function test_RejectsUnsupportedTokenPrecision() public {
        NativePrecisionToken token = new NativePrecisionToken(19);
        vm.expectRevert("Pool: unsupported token decimals");
        pool.addReserve(_config("NEW", address(token)));
    }

    function test_FullPrecisionLegacyRayOperationsAvoidIntermediateOverflow() public pure {
        require(MathLib.rayMul(type(uint256).max, 1e18) == type(uint256).max, "ray multiply");
        require(MathLib.rayDiv(type(uint256).max, 1e18) == type(uint256).max, "ray divide");
    }

    function test_PositionDebtGetterAccruesWithoutPersistingIndexes() public {
        _deposit(alice, USDT_ID, address(usdt), 100_000e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, USDT_ID, 5_000e18, 0.05e18);
        uint256 indexBefore = pool.getReserve(USDT_ID).borrowLiquidityIndex;
        vm.warp(block.timestamp + 90 days);
        (bool ok, bytes memory data) =
            address(pool).staticcall(abi.encodeWithSignature("getPositionDebt(address,uint256)", bob, 0));
        assertTrue(ok, "position debt getter missing");
        uint256 debt = abi.decode(data, (uint256));
        assertGt(debt, 5_000e18);
        assertEq(debt, pool.getUserBorrowBalance(USDT_ID, bob));
        assertEq(pool.getReserve(USDT_ID).borrowLiquidityIndex, indexBefore);
    }

    function _reservedCashFixture() internal {
        _deposit(alice, USDT_ID, address(usdt), 100_000e18);
        _deposit(alice, WBTC_ID, address(wbtc), 10e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, USDT_ID, 10_000e18, 0.05e18);
    }

    function test_BorrowCannotSpendAnotherPositionsReservedCollateral() public {
        _reservedCashFixture();
        uint256 cash = weth.balanceOf(address(pool));
        vm.prank(alice);
        vm.expectRevert("BorrowModule: insufficient available cash");
        pool.borrow(WBTC_ID, WETH_ID, 6e18, 0.05e18);
        assertEq(weth.balanceOf(address(pool)), cash);
        assertEq(pool.getUserPositions(alice).length, 0);
    }

    function test_WithdrawalCannotSpendReservedCollateral() public {
        _reservedCashFixture();
        _borrow(alice, WBTC_ID, WETH_ID, 5e18, 0.05e18);
        uint256 freeClaim = pool.getUserDepositBalance(WETH_ID, bob);
        vm.prank(bob);
        vm.expectRevert("SupplyModule: insufficient available cash");
        pool.withdraw(WETH_ID, 1e18);
        assertEq(pool.getUserDepositBalance(WETH_ID, bob), freeClaim);
        assertEq(weth.balanceOf(address(pool)), 5e18);
    }

    function test_NewCollateralLockRequiresUnreservedCashBacking() public {
        _reservedCashFixture();
        _borrow(alice, WBTC_ID, WETH_ID, 5e18, 0.05e18);
        uint256 freeClaim = pool.getUserDepositBalance(WETH_ID, bob);
        vm.prank(bob);
        vm.expectRevert("BorrowModule: collateral cash unavailable");
        pool.borrow(WETH_ID, USDT_ID, 5_000e18, 0.05e18);
        assertEq(pool.getUserDepositBalance(WETH_ID, bob), freeClaim);
        assertEq(pool.getUserPositions(bob).length, 1);
    }

    function test_ZeroDecimalCollateralCanBorrowAndFullyExit() public {
        (, bytes32 id) = _nativeReserve(0);
        _deposit(alice, USDT_ID, address(usdt), 10_000e18);
        vm.prank(bob);
        pool.deposit(id, 100);
        _borrow(bob, id, USDT_ID, 16e18, 0.05e18);
        assertEq(pool.getPosition(bob, 0).collateralLocked, 21);
        assertTrue(pool.checkPositionHealth(bob, 0));
        vm.startPrank(bob);
        usdt.approve(address(pool), type(uint256).max);
        pool.repay(id, USDT_ID, 0, type(uint256).max);
        pool.withdraw(id, 100);
        vm.stopPrank();
        assertEq(pool.getUserDepositBalance(id, bob), 0);
        assertEq(pool.getReserve(id).totalDeposits, 0);
    }

    function test_EightDecimalCollateralLiquidatesAgainstEighteenDecimalDebt() public {
        (NativePrecisionToken token, bytes32 id) = _nativeReserve(8);
        _deposit(alice, WETH_ID, address(weth), 10e18);
        vm.prank(bob);
        pool.deposit(id, 10_000e8);
        _borrow(bob, id, WETH_ID, 1e18, 0.05e18);
        assertEq(pool.getPosition(bob, 0).collateralLocked, 3_937.5e8);
        oracle.setPrice(wethFeed, 3_500e18);
        uint256 beforeTokens = token.balanceOf(alice);
        uint256 beforePayment = weth.balanceOf(alice);
        vm.prank(alice);
        weth.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        pool.liquidate(bob, 0);
        assertEq(token.balanceOf(alice) - beforeTokens, 3_675e8);
        assertEq(beforePayment - weth.balanceOf(alice), 1e18);
        assertEq(pool.getUserBorrowBalance(WETH_ID, bob), 0);
    }

    function test_CompoundIndexAvoidsRateTimeIntermediateOverflow() public pure {
        uint256 rate = type(uint256).max / 2;
        uint256 increment = rate / 31_536_000 * 3 + (rate % 31_536_000) * 3 / 31_536_000;
        assertEq(MathLib.compoundIndex(1e18, rate, 3), 1e18 + increment);
    }

    function test_ConstructorRejectsOracleWithoutCode() public {
        vm.expectRevert("Pool: oracle has no code");
        new Pool(address(0x1234));
    }

    function test_ReserveRequiresContractTokenAndStrategy() public {
        DataTypes.ReserveConfig memory cfg = _config("NEW", address(0x1234));
        vm.expectRevert("Pool: token has no code");
        pool.addReserve(cfg);
        cfg.tokenAddress = address(new NativePrecisionToken(18));
        cfg.interestStrategy = address(0x1234);
        vm.expectRevert("Pool: strategy has no code");
        pool.addReserve(cfg);
    }

    function test_ReserveRequiresPositiveCaps() public {
        DataTypes.ReserveConfig memory cfg = _config("NEW", address(new NativePrecisionToken(18)));
        cfg.supplyCap = 0;
        vm.expectRevert("Pool: invalid supply cap");
        pool.addReserve(cfg);
        cfg.supplyCap = SUPPLY_CAP;
        cfg.borrowCap = 0;
        vm.expectRevert("Pool: invalid borrow cap");
        pool.addReserve(cfg);
    }
}
