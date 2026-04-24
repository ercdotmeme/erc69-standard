// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

/// @title ERC-69 — Meme Token Standard (factory-deployed variant)
/// @notice No owner, no mint, no pause, no blacklist, no upgrade.
/// @dev Deployed by ERC69Factory. Factory mints 100% to itself, ships 0.69%
///      to a hardcoded address, adds 99.31% + 0.01 ETH to Uniswap LP, burns
///      the LP. Launch window = 9 minutes from deploy. Inside it: 6% buy /
///      9% sell, maxTx / maxWallet = 0.69% of supply, and accumulated sell
///      tax auto-swaps to ETH (capped at 0.5% of supply per swap) and is sent
///      to taxReceiver. After launch window: 0.69% flat, limits lifted,
///      accumulated tax burns to 0x...dEaD every 69 blocks (no ETH swap).
contract MYTOKEN {
    // ─────────────────────────── TOKEN CONFIG ───────────────────────────

    string public constant name = "My Token";
    string public constant symbol = "MYTOKEN";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 69_000_000_000 * 10**18;

    address public constant uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    // ─────────────────────────── TAX CONFIG ─────────────────────────────

    uint256 public constant TAX_BPS = 69;            // 0.69% steady-state
    uint256 public constant LAUNCH_BUY_BPS = 600;    // 6% during launch window
    uint256 public constant LAUNCH_SELL_BPS = 900;   // 9% during launch window
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant LAUNCH_DURATION = 9 minutes;
    uint256 public constant BURN_INTERVAL = 69;      // blocks (post-launch burn cadence)
    uint256 public constant MAX_SWAP_BPS = 50;       // 0.5% of supply cap per launch-window swap
    uint256 public constant SWAP_THRESHOLD = 35_000_000 * 10**18; // don't swap dust

    // Launch-window anti-whale limits: 0.69% of supply each.
    uint256 public constant MAX_TX_BPS = 69;
    uint256 public constant MAX_WALLET_BPS = 69;
    uint256 public constant maxTx = (totalSupply * MAX_TX_BPS) / BPS_DENOMINATOR;
    uint256 public constant maxWallet = (totalSupply * MAX_WALLET_BPS) / BPS_DENOMINATOR;

    // ─────────────────────────── ERC-20 STATE ───────────────────────────

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value); 

    // ─────────────────────────── IMMUTABLE STATE ────────────────────────

    address public immutable uniswapPair;
    address public immutable deployer;      // the factory — tax-exempt so LP add / 1% ship don't get taxed
    address public immutable taxReceiver;   // receives ETH from launch-window swaps
    uint256 public immutable launchTimestamp;

    // ─────────────────────────── MUTABLE STATE ──────────────────────────

    uint256 public lastBurnBlock;
    bool private inSwap;

    // ─────────────────────────── EVENTS ─────────────────────────────────

    event TaxBurned(uint256 amount, uint256 atBlock);
    event TaxSwapped(uint256 tokensIn);
    event TaxSwapFailed(uint256 tokensIn);
    event ETHRescued(address indexed to, uint256 amount);

    // ─────────────────────────── MODIFIERS ──────────────────────────────

    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    // ─────────────────────────── CONSTRUCTOR ────────────────────────────

    constructor(address _taxReceiver) {
        require(_taxReceiver != address(0), "ERC69: zero taxReceiver");

        deployer = msg.sender;
        taxReceiver = _taxReceiver;

        // Mint entire supply to the factory. Factory will push 0.69% to a
        // hardcoded address and 99.31% into LP, leaving itself with 0 tokens.
        _balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);

        IUniswapV2Router02 router = IUniswapV2Router02(uniswapRouter);
        uniswapPair = IUniswapV2Factory(router.factory()).createPair(address(this), router.WETH());

        launchTimestamp = block.timestamp;
        lastBurnBlock = block.number;
    }

    // ─────────────────────────── ERC-20 INTERFACE ───────────────────────

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner_, address spender) external view returns (uint256) {
        return allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= value, "ERC69: allowance");
            unchecked { _allowances[from][msg.sender] = allowed - value; }
        }
        _transfer(from, to, value);
        return true;
    }

    // ─────────────────────────── CORE TRANSFER ──────────────────────────

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0) && to != address(0), "ERC69: zero addr");
        require(_balances[from] >= value, "ERC69: balance");

        // Tax-exempt paths:
        //  - contract's own moves (tax routing / swap)
        //  - inSwap (router callbacks during our own swap)
        //  - deployer (factory) — needed so the one-shot LP add + 1% ship aren't taxed;
        //    factory has no post-construction entry point so it can't be reused as a bypass.
        bool skipTax = (from == address(this) || to == address(this) || inSwap || from == deployer);

        bool isBuy = (from == uniswapPair);
        bool isSell = (to == uniswapPair);
        bool inLaunchWindow = (block.timestamp < launchTimestamp + LAUNCH_DURATION);

        // Launch-window anti-whale limits (0.69% of supply each):
        //   - maxTx: applies to both buys and sells against the pair
        //   - maxWallet: applies to buys only; pair itself is exempt since LP
        //     reserves can exceed max wallet by design
        // Tax-exempt paths (contract / inSwap / deployer) bypass limits too.
        if (inLaunchWindow && !skipTax) {
            if (isBuy || isSell) {
                require(value <= maxTx, "ERC69: maxTx");
            }
            if (isBuy) {
                require(_balances[to] + value <= maxWallet, "ERC69: maxWallet");
            }
        }

        // Launch-window: swap accumulated tax to ETH on sells.
        // swapAmount = min(contractBalance, hardCap, value) — capping at the
        // user's own sell size is critical. Without it, a small user sell
        // would trigger a huge contract-side dump, cratering the price on a
        // thin launch pool and reverting the user's sell on slippage/K.
        if (inLaunchWindow && !inSwap && isSell && !skipTax) {
            uint256 contractBalance = _balances[address(this)];
            if (contractBalance >= SWAP_THRESHOLD) {
                uint256 maxSwap = (totalSupply * MAX_SWAP_BPS) / BPS_DENOMINATOR;
                // min(value, min(contractBalance, maxSwap)) — same pattern as master.sol.
                uint256 swapAmount = _min(value, _min(contractBalance, maxSwap));
                _swapTokensForEth(swapAmount);
            }
        }

        uint256 taxAmount;
        if (!skipTax) {
            uint256 taxBps;
            if (inLaunchWindow) {
                if (isBuy) taxBps = LAUNCH_BUY_BPS;
                else if (isSell) taxBps = LAUNCH_SELL_BPS;
                else taxBps = TAX_BPS;
            } else {
                taxBps = TAX_BPS;
            }
            // Ceiling division — any non-zero taxed transfer pays ≥ 1 wei,
            // closing the "dust round-to-zero" loophole.
            taxAmount = (value * taxBps + BPS_DENOMINATOR - 1) / BPS_DENOMINATOR;
            if (taxAmount > value) taxAmount = value;
        }

        uint256 netAmount = value - taxAmount;

        unchecked {
            _balances[from] -= value;
            _balances[to] += netAmount;
            if (taxAmount != 0) _balances[address(this)] += taxAmount;
        }

        if (taxAmount != 0) emit Transfer(from, address(this), taxAmount);
        emit Transfer(from, to, netAmount);

        // Post-launch: flush accumulated tax to dead every BURN_INTERVAL blocks.
        if (!inLaunchWindow && block.number >= lastBurnBlock + BURN_INTERVAL) {
            _burnAccumulated();
        }
    }

    // ─────────────────────────── INTERNAL: HELPERS ──────────────────────

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    // ─────────────────────────── INTERNAL: SWAP ─────────────────────────

    function _swapTokensForEth(uint256 amount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = IUniswapV2Router02(uniswapRouter).WETH();

        _allowances[address(this)][uniswapRouter] = amount;
        emit Approval(address(this), uniswapRouter, amount);

        // try/catch: if the nested swap reverts for ANY reason (taxReceiver
        // rejects ETH, tiny-pool K-invariant edge case, etc.), the user's
        // outer sell must still succeed. Tax was already collected; the
        // tokens just sit in the contract until the next successful swap
        // or until the post-launch burn.
        try IUniswapV2Router02(uniswapRouter).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            taxReceiver,
            block.timestamp
        ) {
            emit TaxSwapped(amount);
        } catch {
            // Clear the stale allowance the router would have consumed on success.
            _allowances[address(this)][uniswapRouter] = 0;
            emit TaxSwapFailed(amount);
        }
    }

    // ─────────────────────────── INTERNAL: BURN ─────────────────────────

    function _burnAccumulated() internal {
        lastBurnBlock = block.number;
        uint256 bal = _balances[address(this)];
        if (bal == 0) return;
        unchecked {
            _balances[address(this)] = 0;
            _balances[DEAD] += bal;
        }
        emit Transfer(address(this), DEAD, bal);
        emit TaxBurned(bal, block.number);
    }

    // ─────────────────────────── PUBLIC TRIGGER ─────────────────────────

    /// @notice Anyone can poke the burn post-launch once 69 blocks have elapsed.
    function triggerBurn() external {
        require(block.timestamp >= launchTimestamp + LAUNCH_DURATION, "ERC69: still in launch");
        require(block.number >= lastBurnBlock + BURN_INTERVAL, "ERC69: too early");
        _burnAccumulated();
    }

    // ─────────────────────────── ETH RESCUE ─────────────────────────────

    /// @notice Rescue ETH that got stuck in the contract.
    /// @dev Contract has no receive()/fallback, so normal sends revert. This
    ///      exists only to recover ETH force-sent via selfdestruct or
    ///      pre-deploy funding. Gated to taxReceiver — the only "owner-ish"
    ///      role in the contract. Always sends to taxReceiver (not msg.sender)
    ///      so even if the key is compromised, funds only move to the
    ///      pre-committed address.
    function rescueStuckETH() external {
        require(msg.sender == taxReceiver, "ERC69: only taxReceiver");
        uint256 bal = address(this).balance;
        require(bal > 0, "ERC69: no ETH");
        (bool ok, ) = taxReceiver.call{value: bal}("");
        require(ok, "ERC69: ETH send failed");
        emit ETHRescued(taxReceiver, bal);
    }
}