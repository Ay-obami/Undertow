// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Pool} from "../../src/modules/Pool.sol";
import {ChainlinkOracle} from "../../src/oracle/ChainlinkOracle.sol";
import {VariableInterestStrategy} from "../../src/modules/VariableInterestStrategy.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @notice Opt-in, real Ethereum token/feed integration at a fixed historical block.
contract PinnedForkTest is Test {
    uint256 internal constant FORK_BLOCK = 26_088_938;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

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

    function test_PinnedEthereumRealTokenLifecycle() public {
        string memory rpc = vm.envOr("LENDING_FORK_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc, FORK_BLOCK);
        assertEq(block.number, FORK_BLOCK);
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
        deal(USDC, lender, 10_000e6);
        deal(USDC, borrower, 2_000e6);
        deal(WETH, borrower, 1e18);
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
