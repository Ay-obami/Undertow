// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Pool} from "../src/modules/Pool.sol";
import {ChainlinkOracle} from "../src/oracle/ChainlinkOracle.sol";
import {VariableInterestStrategy} from "../src/modules/VariableInterestStrategy.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockOracle} from "../test/mocks/MockOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Set DEPLOY_LOCAL=true to use MockOracle + MockERC20s (local / testnet).
///      For mainnet, set DEPLOY_LOCAL=false and supply real addresses via env vars.
contract Deploy is Script {
    uint256 constant RAY = 1e18;
    bool constant DEPLOY_LOCAL = true;

    function run() external {
        vm.startBroadcast();
        // `deployer` must be read after startBroadcast() — pre-broadcast,
        // msg.sender in a forge script is Foundry's internal default
        // sender, not the account whose key actually broadcasts. Here that
        // would just mint the local mock tokens to the wrong address; see
        // scripts/DeployCoston2.s.sol and DeployAccountLayer.s.sol for a
        // case where getting this wrong is far more serious (permanently
        // locks contract ownership to an unrecoverable address).
        address deployer = msg.sender;

        // ── 1. Deploy shared infrastructure ──────────────────────────
        VariableInterestStrategy strategy = new VariableInterestStrategy();

        address oracleAddr;
        address usdtAddr;
        address wethAddr;
        address wbtcAddr;
        address usdtFeed;
        address wethFeed;
        address wbtcFeed;

        if (DEPLOY_LOCAL) {
            // Mock oracle — prices set manually
            MockOracle mockOracle = new MockOracle();

            MockERC20 usdt = new MockERC20("Mock USDT", "mUSDT");
            MockERC20 weth = new MockERC20("Mock WETH", "mWETH");
            MockERC20 wbtc = new MockERC20("Mock WBTC", "mWBTC");

            // Synthetic feed addresses (just labels for the mock)
            usdtFeed = address(0xFEED1);
            wethFeed = address(0xFEED2);
            wbtcFeed = address(0xFEED3);

            mockOracle.setPrice(usdtFeed, 1 * RAY);
            mockOracle.setPrice(wethFeed, 3_000 * RAY);
            mockOracle.setPrice(wbtcFeed, 60_000 * RAY);

            oracleAddr = address(mockOracle);
            usdtAddr   = address(usdt);
            wethAddr   = address(weth);
            wbtcAddr   = address(wbtc);

            usdt.mint(deployer, 1_000_000e18);
            weth.mint(deployer, 1_000e18);
            wbtc.mint(deployer, 100e18);
        } else {
            // Production: real Chainlink oracle (24h stale period)
            ChainlinkOracle chainlinkOracle = new ChainlinkOracle(24 hours);
            oracleAddr = address(chainlinkOracle);

            // Read real token + feed addresses from env
            usdtAddr = vm.envAddress("TOKEN_USDT");
            wethAddr = vm.envAddress("TOKEN_WETH");
            wbtcAddr = vm.envAddress("TOKEN_WBTC");
            usdtFeed = vm.envAddress("FEED_USDT");
            wethFeed = vm.envAddress("FEED_WETH");
            wbtcFeed = vm.envAddress("FEED_WBTC");
        }

        // ── 2. Deploy Pool ────────────────────────────────────────────
        Pool pool = new Pool(oracleAddr);

        // ── 3. Register reserves ──────────────────────────────────────
        pool.addReserve(DataTypes.ReserveConfig({
            name:                 "mUSDT",
            tokenAddress:         usdtAddr,
            priceFeed:            usdtFeed,
            interestStrategy:     address(strategy),
            liquidationThreshold: 85 * RAY / 100,
            ltv:                  80 * RAY / 100,
            slope1:               4  * RAY / 100,
            slope2:               60 * RAY / 100,
            baseInterestRate:     2  * RAY / 100,
            optimalUtilization:   80 * RAY / 100,
            liquidationBonus:     5  * RAY / 100,
            reserveFactor:        10 * RAY / 100,
            borrowCap:            1_000_000e18,
            supplyCap:            1_000_000e18,
            isActive:             true,
            isBorrowable:         true
        }));

        pool.addReserve(DataTypes.ReserveConfig({
            name:                 "mWETH",
            tokenAddress:         wethAddr,
            priceFeed:            wethFeed,
            interestStrategy:     address(strategy),
            liquidationThreshold: 80 * RAY / 100,
            ltv:                  75 * RAY / 100,
            slope1:               5  * RAY / 100,
            slope2:               80 * RAY / 100,
            baseInterestRate:     2  * RAY / 100,
            optimalUtilization:   80 * RAY / 100,
            liquidationBonus:     8  * RAY / 100,
            reserveFactor:        15 * RAY / 100,
            borrowCap:            10_000e18,
            supplyCap:            10_000e18,
            isActive:             true,
            isBorrowable:         true
        }));

        pool.addReserve(DataTypes.ReserveConfig({
            name:                 "mWBTC",
            tokenAddress:         wbtcAddr,
            priceFeed:            wbtcFeed,
            interestStrategy:     address(strategy),
            liquidationThreshold: 75 * RAY / 100,
            ltv:                  70 * RAY / 100,
            slope1:               5  * RAY / 100,
            slope2:               100 * RAY / 100,
            baseInterestRate:     2  * RAY / 100,
            optimalUtilization:   65 * RAY / 100,
            liquidationBonus:     10 * RAY / 100,
            reserveFactor:        20 * RAY / 100,
            borrowCap:            1_000e18,
            supplyCap:            1_000e18,
            isActive:             true,
            isBorrowable:         true
        }));

        // ── 4. Seed initial liquidity (local only) ────────────────────
        if (DEPLOY_LOCAL) {
            IERC20(usdtAddr).approve(address(pool), 500_000e18);
            IERC20(wethAddr).approve(address(pool), 500e18);
            IERC20(wbtcAddr).approve(address(pool), 50e18);

            bytes32 usdtId = pool.getReserveId("mUSDT");
            bytes32 wethId = pool.getReserveId("mWETH");
            bytes32 wbtcId = pool.getReserveId("mWBTC");

            pool.deposit(usdtId, 500_000e18);
            pool.deposit(wethId, 500e18);
            pool.deposit(wbtcId, 50e18);
        }

        vm.stopBroadcast();

        // ── 5. Log addresses ──────────────────────────────────────────
        console.log("Pool deployed at:      ", address(pool));
        console.log("Strategy deployed at:  ", address(strategy));
        console.log("Oracle deployed at:    ", oracleAddr);
        console.log("mUSDT deployed at:     ", usdtAddr);
        console.log("mWETH deployed at:     ", wethAddr);
        console.log("mWBTC deployed at:     ", wbtcAddr);
    }
}
