// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Pool} from "../../src/modules/Pool.sol";
import {ChainlinkOracle} from "../../src/oracle/ChainlinkOracle.sol";
import {VariableInterestStrategy} from "../../src/modules/VariableInterestStrategy.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

contract NativePrecisionToken is ERC20 {
    uint8 private immutable precision;

    constructor(uint8 p) ERC20("Smoke token", "SMOKE") {
        precision = p;
    }

    function decimals() public view override returns (uint8) {
        return precision;
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract SmokePriceFeed {
    int256 private immutable price;
    uint256 private immutable timestamp;

    constructor(int256 p) {
        price = p;
        timestamp = block.timestamp;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, price, timestamp, timestamp, 1);
    }
}

/// @notice Local deployment lifecycle with six/eighteen-decimal tokens and the real oracle adapter.
contract DeployedLifecycleTest is Test {
    function _add(Pool pool, address strategy, string memory name, address token, address feed) internal {
        pool.addReserve(
            DataTypes.ReserveConfig({
                name: name,
                tokenAddress: token,
                priceFeed: feed,
                interestStrategy: strategy,
                liquidationThreshold: 0.85e18,
                ltv: 0.8e18,
                slope1: 0.04e18,
                slope2: 0.6e18,
                baseInterestRate: 0.02e18,
                optimalUtilization: 0.8e18,
                liquidationBonus: 0.05e18,
                reserveFactor: 0.1e18,
                borrowCap: type(uint128).max,
                supplyCap: type(uint128).max,
                isActive: true,
                isBorrowable: true
            })
        );
    }

    function test_DeployedMixedDecimalLifecycle() public {
        vm.warp(10_000);
        address USDC = address(new NativePrecisionToken(6));
        address WETH = address(new NativePrecisionToken(18));
        address USDC_USD = address(new SmokePriceFeed(1e8));
        address ETH_USD = address(new SmokePriceFeed(3_000e8));
        assertEq(IERC20Metadata(USDC).decimals(), 6);
        assertEq(IERC20Metadata(WETH).decimals(), 18);
        ChainlinkOracle oracle = new ChainlinkOracle(7 days);
        uint256 usdcPrice = oracle.getPrice(USDC_USD);
        uint256 wethPrice = oracle.getPrice(ETH_USD);
        assertGt(usdcPrice, 0.95e18);
        assertLt(usdcPrice, 1.05e18);
        assertGt(wethPrice, 1_000e18);

        Pool pool = new Pool(address(oracle));
        VariableInterestStrategy strategy = new VariableInterestStrategy();
        _add(pool, address(strategy), "USDC", USDC, USDC_USD);
        _add(pool, address(strategy), "WETH", WETH, ETH_USD);
        bytes32 usdcId = pool.getReserveId("USDC");
        bytes32 wethId = pool.getReserveId("WETH");
        address lender = makeAddr("fork-lender");
        address borrower = makeAddr("fork-borrower");
        NativePrecisionToken(USDC).mint(lender, 10_000e6);
        NativePrecisionToken(USDC).mint(borrower, 2_000e6);
        NativePrecisionToken(WETH).mint(borrower, 1e18);
        vm.startPrank(lender);
        IERC20Metadata(USDC).approve(address(pool), type(uint256).max);
        pool.deposit(usdcId, 10_000e6);
        vm.stopPrank();
        vm.startPrank(borrower);
        IERC20Metadata(WETH).approve(address(pool), type(uint256).max);
        IERC20Metadata(USDC).approve(address(pool), type(uint256).max);
        pool.deposit(wethId, 1e18);
        uint256 beforeUSDC = IERC20Metadata(USDC).balanceOf(borrower);
        pool.borrow(wethId, usdcId, 1_000e6, 0.05e18);
        assertEq(IERC20Metadata(USDC).balanceOf(borrower) - beforeUSDC, 1_000e6);
        DataTypes.Position memory position = pool.getPosition(borrower, 0);
        // Independent economic lower bound: borrowed USD must be covered at 80% LTV.
        uint256 debtUSD = 1_000 * usdcPrice;
        uint256 lockedUSD = position.collateralLocked * wethPrice / 1e18;
        assertGe(lockedUSD * 8 / 10, debtUSD, "native token decimals undervalue required collateral");
        vm.warp(block.timestamp + 1 days);
        uint256 debt = pool.getUserBorrowBalance(usdcId, borrower);
        assertGt(debt, 1_000e6);
        pool.repay(wethId, usdcId, 0, type(uint256).max);
        assertEq(pool.getUserBorrowBalance(usdcId, borrower), 0);
        vm.expectRevert("PoolStorage: position closed");
        pool.getPosition(borrower, 0);
        pool.withdraw(wethId, pool.getUserDepositBalance(wethId, borrower));
        assertGe(IERC20Metadata(WETH).balanceOf(borrower), 1e18 - 1);
        vm.stopPrank();
        vm.startPrank(lender);
        pool.withdraw(usdcId, pool.getUserDepositBalance(usdcId, lender));
        vm.stopPrank();
        assertEq(pool.getReserve(usdcId).totalDeposits, 0);
        assertEq(pool.getReserve(usdcId).totalBorrows, 0);
    }
}
