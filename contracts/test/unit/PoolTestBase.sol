// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Pool} from "../../src/modules/Pool.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {VariableInterestStrategy} from "../../src/modules/VariableInterestStrategy.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";



/// @notice Shared base — deploy stack + helpers every test inherits.
abstract contract PoolTestBase is Test {
    Pool                    internal pool;
    MockOracle              internal oracle;
    VariableInterestStrategy internal strategy;

    MockERC20 internal usdt;
    MockERC20 internal weth;
    MockERC20 internal wbtc;

    // Synthetic price feed addresses (just labels — MockOracle maps them)
    address internal usdtFeed = address(0xFEED1);
    address internal wethFeed = address(0xFEED2);
    address internal wbtcFeed = address(0xFEED3);

    bytes32 internal USDT_ID;
    bytes32 internal WETH_ID;
    bytes32 internal WBTC_ID;

    address internal alice = makeAddr("alice");
    address internal bob   = makeAddr("bob");

    uint256 constant RAY = 1e18;

    // ── Default risk params ──────────────────────────────────────────

    uint256 constant LIQ_THRESHOLD = 85 * RAY / 100;   // 85 %
    uint256 constant LTV           = 80 * RAY / 100;   // 80 %
    uint256 constant SLOPE1        =  4 * RAY / 100;   //  4 %
    uint256 constant SLOPE2        = 60 * RAY / 100;   // 60 %
    uint256 constant BASE_RATE     =  2 * RAY / 100;   //  2 %
    uint256 constant OPT_UTIL      = 80 * RAY / 100;   // 80 %
    uint256 constant LIQ_BONUS     =  5 * RAY / 100;   //  5 %
    uint256 constant RESERVE_FACTOR = 10 * RAY / 100;  // 10 %
    uint256 constant BORROW_CAP    = 1_000_000e18;
    uint256 constant SUPPLY_CAP    = 1_000_000e18;

    function setUp() public virtual {
        oracle   = new MockOracle();
        strategy = new VariableInterestStrategy();
        pool     = new Pool(address(oracle));

        usdt = new MockERC20("Mock USDT", "mUSDT");
        weth = new MockERC20("Mock WETH", "mWETH");
        wbtc = new MockERC20("Mock WBTC", "mWBTC");

        // RAY-scaled prices
        oracle.setPrice(usdtFeed, 1 * RAY);
        oracle.setPrice(wethFeed, 3_000 * RAY);
        oracle.setPrice(wbtcFeed, 60_000 * RAY);

        _addReserve("mUSDT", address(usdt), usdtFeed);
        _addReserve("mWETH", address(weth), wethFeed);
        _addReserve("mWBTC", address(wbtc), wbtcFeed);

        USDT_ID = pool.getReserveId("mUSDT");
        WETH_ID = pool.getReserveId("mWETH");
        WBTC_ID = pool.getReserveId("mWBTC");

        // Fund users
        usdt.mint(alice, 1_000_000e18);
        usdt.mint(bob,   1_000_000e18);
        weth.mint(alice, 1_000e18);
        weth.mint(bob,   1_000e18);
        wbtc.mint(alice, 100e18);
        wbtc.mint(bob,   100e18);
    }

    // ── Helpers ──────────────────────────────────────────────────────

    function _addReserve(string memory name, address token, address feed) internal {
        pool.addReserve(DataTypes.ReserveConfig({
            name:                 name,
            tokenAddress:         token,
            priceFeed:            feed,
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

    function _deposit(address user, bytes32 reserveId, address token, uint256 amount) internal {
        vm.startPrank(user);
        MockERC20(token).approve(address(pool), amount);
        pool.deposit(reserveId, amount);
        vm.stopPrank();
    }

    function _borrow(
        address user,
        bytes32 collateralId,
        bytes32 borrowId,
        uint256 amount,
        uint256 bufferPct
    ) internal {
        vm.prank(user);
        pool.borrow(collateralId, borrowId, amount, bufferPct);
    }
}
