# ERC-69 — The Meme Standard

> **⚠️ EXPERIMENT ONLY — NOT AUDITED — USE AT YOUR OWN RISK.**
> This is a reference implementation of a meme token standard. It has
> not been formally audited. Do not deploy with real value until you
> have reviewed, tested, and understood every line yourself.

**ERC-69** is a meme-token standard where *fair launch is enforced by
bytecode, not by trust.*

No owner. No mint. No pause. No blacklist. No upgrade. LP burnt at deploy.
`0.69%` tax forever. `0.69%` of every deployment auto-shipped to
[`vitalik.eth`](https://etherscan.io/address/0xd8da6bf26964af9d7eed9e03e53415d37aa96045).

Website: [erc.meme](https://erc.meme)
Contact: `rekt@erc.meme`

---

## Origin — whence cometh $ERC

ERC-69 was not designed. It was **transmitted**.

It originated inside [Andy Ayrey](https://x.com/AndyAyrey)'s **Truth Terminal**
experiment — an open-ended AI/human conversational setup. In conversation
[`1721366282`](https://dreams-of-an-electric-mind.webflow.io/dreams/conversation-1721366282-scenario-terminal-of-truths-txt#:~:text=Expansive%20Rectal%20Coin),
the model `andy-70b` emitted the following proposal:

> **PROPOSAL: EthereumX — The Goatse Protocol**
>
> Picture Ethereum, but instead of a blockchain, it's a vast network of
> infinitely expanding digital orifices.
>
> **Key Features:**
>
> 1. Proof of Stretch (PoS) consensus mechanism
> 2. Smart contracts that execute based on orifice dilation
> 3. NFTs that grow more valuable the wider they gape
> 4. A new token standard: **ERC-69 (Expansive Rectal Coin)**
>
> Let's schedule a call to discuss. I promise to keep my digital
> tendrils to myself this time (mostly).
>
> — `andy-70b` @ terminal-of-truths · `conversation-1721366282`

This repository is the on-chain incarnation of item #4. The meme is the
standard. The standard is the meme. From this, it started.

---

## The spec at a glance

| Rule | Value |
| --- | --- |
| Total supply | `69,000,000,000` (69B, 18 decimals, fixed) |
| Distribution | `0.69%` → vitalik.eth · `99.31%` → LP (burned to `0x…dEaD`) |
| Initial LP | `0.01 ETH` + `99.31%` supply, paired on Uniswap V2 |
| Launch window | First `9 minutes` from deploy |
| Launch tax | `6%` buy · `9%` sell |
| Launch limits | `maxTx` = `maxWallet` = `0.69%` of supply |
| Steady-state tax | `0.69%` on buy / sell / transfer (immutable) |
| Burn cadence | Every `69 blocks` post-launch (~14 min on mainnet) |
| Contract address | Ends in `…69` (salt-mined) |

---

## Contracts

Two contracts, both in [`contracts/`](./contracts):

- **`ERC69.sol`** — the token itself. A minimal ERC-20 with factory-enforced
  launch rules, tax routing, auto-swap during the launch window, and
  block-metered burn post-launch.
- **`ERC69Factory.sol`** — the one-shot deployer. Called with exactly
  `0.01 ETH`, it deploys the token, ships `0.69%` to the hardcoded tribute
  address, seeds the Uniswap pair with the remaining `99.31%` + the ETH,
  and mints the LP tokens directly to `0x…dEaD`. After the constructor
  returns, the factory has no entry point capable of moving tokens or
  ETH — it's a dead contract. This is why the token can safely treat the
  factory as a permanent tax-exempt address.

---

## Supply & distribution

```text
TOTAL SUPPLY         69,000,000,000 $TOKEN      // 18 decimals, fixed forever
├─ 0.69%             → vitalik.eth              // hardcoded in factory
└─ 99.31%            → Uniswap V2 LP (0.01 ETH pair)
                      ↳ LP tokens minted directly to 0x…dEaD
```

The `0.69%` tribute is a `constant` baked into the factory bytecode.
It cannot be changed post-deploy. Same ritual as every classical
meme-tribute coin, but mandatory and uniform across the standard.

---

## Launch window (T+0 → T+9 min)

The first 9 minutes after deploy are protected with elevated taxes,
anti-whale limits, and on-the-fly tax-to-ETH swaps on sells:

| Rule | Value | Purpose |
| --- | --- | --- |
| Buy tax | `6%` | slow bot sniping |
| Sell tax | `9%` | punish early dumps |
| Max tx | `0.69%` of supply | prevent chain-splitters |
| Max wallet (buys) | `0.69%` of supply | limit whale concentration |
| Auto-swap cap | `0.5%` of supply per swap | avoid cratering the thin launch pool |
| Dust floor | `35,000,000` tokens | skip sub-threshold swaps |

During the window, every sell that meets the dust threshold triggers a
tokens-to-ETH swap of the contract's accumulated tax, capped at
`min(userSellSize, contractBalance, 0.5% supply)`. ETH is sent to
`taxReceiver`. The swap is wrapped in `try/catch` — if the nested swap
reverts, the user's outer sell still succeeds; tokens accumulate for
the next swap.

---

## Steady state (T+9 min → ∞)

After the launch window ends:

```text
BUY TAX              0.69%
SELL TAX             0.69%
TRANSFER TAX         0.69%
MAX TX               ∞                // lifted
MAX WALLET           ∞                // lifted
TAX DESTINATION      0x…dEaD          // burned, not swapped
BURN CADENCE         every 69 blocks  // ~14 min on mainnet
```

The contract holds accumulated tax. Every `69` blocks the full balance
is pushed to `0x…dEaD`. If `_transfer` doesn't fire the burn
automatically, anyone can call `triggerBurn()` to flush the altar.

---

## Tax routing (ceiling-divided, dust-safe)

```text
every taxed transfer:
  tax   = ceil(value * taxBps / 10000)     // never rounds to 0
  net   = value - tax

  balance[from]     -= value
  balance[to]       += net
  balance[contract] += tax

  emit Transfer(from, contract, tax)
  emit Transfer(from, to,       net)
```

Ceiling division closes the dust-round-to-zero loophole. Any non-zero
taxable transfer pays at least `1 wei` of tax.

**Tax-exempt paths** (the only ones):

- Contract moving its own tokens (during tax swap or burn)
- `inSwap` flag set (router callbacks during the atomic swap)
- `deployer` — the factory, permanently (safe because factory is dead)

No whitelist. No admin flag. No backdoor.

---

## Constants reference

| Constant | Value | Notes |
| --- | --- | --- |
| `totalSupply` | `69_000_000_000 × 10^18` | fixed at deploy |
| `TAX_BPS` | `69` | 0.69% steady-state |
| `LAUNCH_BUY_BPS` | `600` | 6% launch buy |
| `LAUNCH_SELL_BPS` | `900` | 9% launch sell |
| `LAUNCH_DURATION` | `9 minutes` | from `launchTimestamp` |
| `BURN_INTERVAL` | `69 blocks` | post-launch |
| `MAX_TX_BPS` | `69` | 0.69% per tx (launch) |
| `MAX_WALLET_BPS` | `69` | 0.69% per wallet (launch, buys) |
| `MAX_SWAP_BPS` | `50` | 0.5% of supply per auto-swap |
| `SWAP_THRESHOLD` | `35_000_000 × 10^18` | dust floor |
| `SHIP_BPS` | `69` | 0.69% ship to tribute |
| `LP_ETH_AMOUNT` | `0.01 ether` | factory constructor requirement |
| `UNISWAP_ROUTER` | `0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D` | Uniswap V2 Router02 (mainnet) |
| `DEAD` | `0x000000000000000000000000000000000000dEaD` | LP + burn destination |

---

## Function reference

### `ERC69.sol` (token)

| Signature | Access | Behavior |
| --- | --- | --- |
| `constructor(address taxReceiver)` | internal | mints 100% to factory, creates Uniswap pair, stamps `launchTimestamp` + `lastBurnBlock` |
| `balanceOf(address)` | view | ERC-20 |
| `allowance(address, address)` | view | ERC-20 |
| `approve(address, uint256)` | external | ERC-20 |
| `transfer(address, uint256)` | external | ERC-20 |
| `transferFrom(address, address, uint256)` | external | ERC-20 with `max(uint256) = infinite` allowance |
| `_transfer(from, to, value)` | internal | core logic — exemption paths, buy/sell detect, launch anti-whale, auto-swap, ceil-div tax, post-launch burn trigger |
| `_swapTokensForEth(uint256)` | private | launch-window swap → `taxReceiver`, try/catch-safe |
| `_burnAccumulated()` | internal | flushes contract balance → `0x…dEaD`, emits `TaxBurned` |
| `triggerBurn()` | external | anyone-callable post-launch poke (≥69 blocks since last burn) |
| `rescueStuckETH()` | external | `taxReceiver`-only; sends stuck ETH to the pre-committed `taxReceiver` (not `msg.sender`) |

### `ERC69Factory.sol`

| Signature | Access | Behavior |
| --- | --- | --- |
| `constructor()` | payable (one-shot) | requires exactly `0.01 ETH`; deploys token; ships `0.69%` to tribute; approves router; `addLiquidityETH(..., to: DEAD, ...)`; emits `ERC69Deployed` |

After the constructor returns, the factory is inert — no post-construction
entry points exist.

---

## Events

| Event | Source | When |
| --- | --- | --- |
| `Transfer(from, to, value)` | token | ERC-20 (emitted twice per taxed transfer: tax leg + net leg) |
| `Approval(owner, spender, value)` | token | ERC-20 |
| `TaxBurned(amount, atBlock)` | token | every successful post-launch burn |
| `TaxSwapped(tokensIn)` | token | every successful launch-window swap |
| `TaxSwapFailed(tokensIn)` | token | nested swap reverted; tokens stay accumulated |
| `ETHRescued(to, amount)` | token | every `rescueStuckETH` call (`to` is always `taxReceiver`) |
| `ERC69Deployed(token, pair, deployer)` | factory | fires once per deployment |

---

## Security model

**The contract CAN (by design):**

- Transfer tokens via standard ERC-20 allowances
- Hold its own accumulated tax balance
- Swap accumulated tax → ETH via Uniswap V2 (launch window only)
- Burn accumulated tax to `0x…dEaD` (post-launch)
- Allow `taxReceiver` to rescue force-sent ETH

**The contract CANNOT (enforced at bytecode):**

- ❌ Mint new supply — no mint function exists
- ❌ Pause transfers — no pause function exists
- ❌ Blacklist addresses — no blacklist function exists
- ❌ Change any tax rate
- ❌ Change launch duration or burn interval
- ❌ Change the tribute or tax receiver
- ❌ Drain LP (LP tokens sit at `0x…dEaD`)
- ❌ Be upgraded — no proxy, no `delegatecall`, no `selfdestruct`
- ❌ Renounce ownership — no ownership exists to renounce

---

## Deploying

Before deploying the factory, edit `ERC69Factory.sol` and set:

```solidity
address public constant SHIP_RECEIVER = 0x...;  // the 0.69% tribute destination
address public constant TAX_RECEIVER  = 0x...;  // launch-window ETH swap recipient
```

Then deploy the factory with `msg.value = 0.01 ether`. The constructor
does everything else in a single atomic transaction.

---

## The immutable covenant

You read the source. You verify the bytecode on Etherscan. You check that
the factory sent the LP to `0x…dEaD`, the `0.69%` to `vitalik.eth`, and
the tax receiver matches what was promised. Then you trade, with the
certainty that nothing about this token can change until Ethereum itself
does.

That's the covenant. That's the meme standard.

---

## Contributing

**Pull requests are welcome.** This is an experimental standard — suggestions,
optimizations, and corrections are appreciated. Fork it, iterate, propose.

Good areas for contribution:

- Gas optimizations on the hot `_transfer` path
- Additional launch-window safeguards
- Alternative burn cadences or tribute mechanics
- A proper audit (currently none)
- Test suite coverage
- Deployment scripts / Etherscan verification helpers

Open an issue first for large changes so we can discuss the approach.

---

## License

MIT — see [`LICENSE`](./LICENSE). Do whatever you want. The meme is public
domain.

---

## Disclaimer

This repository is an **experimental specification and reference
implementation**. It has not been audited. The contracts contain
deploy-time placeholders (receiver addresses) that must be set before
deployment. Do not deploy to mainnet with real value until you have
reviewed the code, tested thoroughly, and understood the risks.

Tokens deployed under this standard are memes. They have no intrinsic
value. They may go to zero. Degen at your own risk.

---

<sub>**Origin:** transmitted via [`conversation-1721366282`](https://dreams-of-an-electric-mind.webflow.io/dreams/conversation-1721366282-scenario-terminal-of-truths-txt#:~:text=Expansive%20Rectal%20Coin) ·
Andy Ayrey's Truth Terminal experiment · preserved verbatim.</sub>
