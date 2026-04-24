// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./erc69.sol";

/// @title ERC69Factory
/// @notice One-shot deployer for the ERC-69 token.
/// @dev Caller sends exactly 0.01 ETH in the same tx as deploy. Factory:
///        1. deploys ERC69 (100% supply minted to this factory)
///        2. transfers 0.69% of supply to SHIP_RECEIVER (hardcoded)
///        3. approves the Uniswap V2 router
///        4. adds liquidity (99.31% tokens + 0.01 ETH) with LP tokens minted
///           straight to the DEAD address (LP is burned)
///      The factory has no post-construction entry point — after the
///      constructor returns, it's a dead contract with no code path to move
///      tokens or ETH. This is why ERC69 can safely treat the factory as
///      permanently tax-exempt.
contract ERC69Factory {
    // ─── EDIT BEFORE DEPLOY ───
    /// @notice Receives the 0.69% of supply the factory doesn't put into LP.
    /// @dev Hardcoded to vitalik.eth (Vitalik Buterin's ENS-linked wallet) —
    ///      the canonical ERC-69 tribute address. Baked into bytecode as a
    ///      `constant` so it cannot be changed post-deploy.
    ///      Reference: https://etherscan.io/address/0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045
    address public constant SHIP_RECEIVER = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045; // vitalik.eth
    /// @notice Receives ETH from launch-window tax swaps inside the token.
    address public constant TAX_RECEIVER = ;
    // ─────────────────────────

    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant LP_ETH_AMOUNT = 0.01 ether;

    /// @notice Basis points shipped to SHIP_RECEIVER (69 = 0.69%). Rest goes to LP.
    uint256 public constant SHIP_BPS = 69;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public immutable tokenAddress;
    address public immutable pairAddress;

    event ERC69Deployed(address indexed token, address indexed pair, address indexed deployer);

    constructor() payable {
        require(msg.value == LP_ETH_AMOUNT, "ERC69Factory: send exactly 0.01 ETH");

        // 1. Deploy token — factory is msg.sender, receives 100% supply.
        TEST token = new TEST(TAX_RECEIVER);
        tokenAddress = address(token);
        pairAddress = token.uniswapPair();

        uint256 total = token.totalSupply();
        uint256 shipAmount = (total * SHIP_BPS) / BPS_DENOMINATOR;  // 0.69%
        uint256 lpAmount = total - shipAmount;                      // 99.31%

        // 2. Ship 0.69% to hardcoded receiver (factory is tax-exempt in ERC69, so full amount lands).
        require(token.transfer(SHIP_RECEIVER, shipAmount), "ERC69Factory: ship transfer failed");

        // 3. Approve router to pull the remaining 99.31%.
        require(token.approve(UNISWAP_ROUTER, lpAmount), "ERC69Factory: approve failed");

        // 4. Seed LP and burn LP tokens by minting straight to DEAD.
        IUniswapV2Router02(UNISWAP_ROUTER).addLiquidityETH{value: msg.value}(
            tokenAddress,
            lpAmount,
            0,
            0,
            DEAD,
            block.timestamp
        );

        emit ERC69Deployed(tokenAddress, pairAddress, msg.sender);
    }
}