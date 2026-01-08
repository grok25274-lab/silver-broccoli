// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

/**
 * @title Fee Loss Proof of Concept
 * @notice Demonstrates that 10% of commission fees are lost when builder code is present
 * @dev This PoC shows the mathematical proof without requiring full protocol deployment
 */
contract FeeLossPocTest is Test {
    // Constants from RiskEngine.sol
    uint16 constant PROTOCOL_SPLIT = 6_500;  // 65%
    uint16 constant BUILDER_SPLIT = 2_500;   // 25%
    uint256 constant DECIMALS = 10_000;      // From CollateralTracker

    // Simulated state
    uint256 totalSupply = 1_000_000e18;      // 1M shares
    uint256 totalAssets = 1_000_000e6;       // 1M USDC (6 decimals)

    function setUp() public {}

    /**
     * @notice Proves that PROTOCOL_SPLIT + BUILDER_SPLIT != DECIMALS
     */
    function test_SplitSumIsNot100Percent() public pure {
        uint256 totalSplit = uint256(PROTOCOL_SPLIT) + uint256(BUILDER_SPLIT);

        assertEq(totalSplit, 9000, "Total split should be 9000");
        assertTrue(totalSplit != DECIMALS, "Total split should NOT equal DECIMALS");

        // This proves 10% is unaccounted for
        uint256 lostPercentage = DECIMALS - totalSplit;
        assertEq(lostPercentage, 1000, "10% (1000 bps) is lost");
    }

    /**
     * @notice Simulates the fee distribution logic from settleMint()
     * @dev Shows exact amount of shares that remain with optionOwner
     */
    function test_FeeLossInSettleMint() public {
        // Simulate a position mint with 100,000 USDC notional
        uint256 notionalAmount = 100_000e6;  // 100k USDC
        uint16 notionalFee = 10;             // 10 bps = 0.1%

        // Calculate commission as done in settleMint
        uint128 commission = uint128(notionalAmount);
        uint128 commissionFee = uint128((uint256(commission) * notionalFee + DECIMALS - 1) / DECIMALS);

        // commissionFee = 100,000 * 10 / 10,000 = 100 USDC
        assertEq(commissionFee, 100e6, "Commission should be 100 USDC");

        // Calculate shares to burn (rounded up)
        uint256 sharesToBurn = (uint256(commissionFee) * totalSupply + totalAssets - 1) / totalAssets;

        // Simulate transfers as done when feeRecipient != 0
        uint256 toProtocol = (sharesToBurn * PROTOCOL_SPLIT) / DECIMALS;
        uint256 toBuilder = (sharesToBurn * BUILDER_SPLIT) / DECIMALS;
        uint256 totalTransferred = toProtocol + toBuilder;

        // Calculate what remains with optionOwner (the bug!)
        uint256 remainsWithOwner = sharesToBurn - totalTransferred;

        console.log("=== Fee Loss Demonstration ===");
        console.log("Notional Amount:", notionalAmount / 1e6, "USDC");
        console.log("Commission Fee:", commissionFee / 1e6, "USDC");
        console.log("Shares to Burn:", sharesToBurn);
        console.log("To Protocol (65%):", toProtocol);
        console.log("To Builder (25%):", toBuilder);
        console.log("Total Transferred:", totalTransferred);
        console.log("LOST (remains with owner):", remainsWithOwner);
        console.log("Loss percentage:", (remainsWithOwner * 10000) / sharesToBurn, "bps");

        // Verify the loss is approximately 10%
        // Due to rounding, it should be close to 10% of sharesToBurn
        uint256 expectedLoss = (sharesToBurn * 1000) / DECIMALS;  // 10%

        // Allow for some rounding variance
        assertApproxEqAbs(
            remainsWithOwner,
            expectedLoss,
            2,  // Allow 2 wei variance for rounding
            "Loss should be approximately 10% of shares"
        );

        // Prove loss is non-zero
        assertTrue(remainsWithOwner > 0, "There MUST be a loss");
    }

    /**
     * @notice Demonstrates cumulative loss over multiple transactions
     */
    function test_CumulativeLossOverTime() public {
        uint256 dailyVolume = 10_000_000e6;  // $10M daily volume
        uint16 notionalFee = 10;             // 10 bps

        // Daily commission = $10M * 0.001 = $10,000
        uint256 dailyCommission = (dailyVolume * notionalFee) / DECIMALS;

        // Loss = 10% of commission = $1,000/day
        uint256 dailyLoss = (dailyCommission * 1000) / DECIMALS;

        // Annual loss
        uint256 annualLoss = dailyLoss * 365;

        console.log("=== Cumulative Loss Projection ===");
        console.log("Daily Volume:", dailyVolume / 1e6, "USDC");
        console.log("Daily Commission:", dailyCommission / 1e6, "USDC");
        console.log("Daily Loss (10%):", dailyLoss / 1e6, "USDC");
        console.log("Annual Loss:", annualLoss / 1e6, "USDC");

        // At $10M daily volume, annual loss is $365,000
        assertEq(annualLoss, 365_000e6, "Annual loss should be $365,000");
    }

    /**
     * @notice Comparison: What SHOULD happen vs what DOES happen
     */
    function test_ComparisonCorrectVsBuggyBehavior() public {
        uint256 sharesToBurn = 1000e18;  // 1000 shares

        // BUGGY: Current implementation
        uint256 buggy_toProtocol = (sharesToBurn * PROTOCOL_SPLIT) / DECIMALS;  // 650 shares
        uint256 buggy_toBuilder = (sharesToBurn * BUILDER_SPLIT) / DECIMALS;    // 250 shares
        uint256 buggy_total = buggy_toProtocol + buggy_toBuilder;               // 900 shares
        uint256 buggy_lost = sharesToBurn - buggy_total;                        // 100 shares LOST

        // CORRECT: When feeRecipient == 0 (no builder)
        // All shares are burned via _burn(optionOwner, sharesToBurn)
        uint256 correct_burned = sharesToBurn;  // 1000 shares

        console.log("=== Buggy vs Correct ===");
        console.log("Shares to distribute:", sharesToBurn / 1e18);
        console.log("BUGGY - To Protocol:", buggy_toProtocol / 1e18);
        console.log("BUGGY - To Builder:", buggy_toBuilder / 1e18);
        console.log("BUGGY - Lost:", buggy_lost / 1e18);
        console.log("CORRECT - Burned:", correct_burned / 1e18);

        // The bug causes 10% loss
        assertEq(buggy_lost, 100e18, "100 shares are lost in buggy path");
        assertEq(correct_burned, sharesToBurn, "Correct path burns all shares");
    }
}
