# Eulaunch Contracts

Smart contracts for Eulaunch - a token factory and liquidity bootstrapping platform for EulerSwap.

## How it works

Eulaunch takes a set of token metadata parameters (name, symbol, total supply) and the quote token the user wishes to pair the token with. It finds the quote token vault (usually something liquid like Euler Prime USDC) from a registry, and then handles everything else - deploying a new token, creating an [escrow vault](https://www.euler.finance/blog/euler-v2-the-new-modular-age-of-defi), setting up the EulerSwap curve, etc.

The user becomes the owner of a [`LiquidityManager`](./src/LiquidityManager.sol) contract that acts as the liquidity provider of the EulerSwap pool. They can then close the pool at any time, and the funds will be redeemed to them - or, of course, they can renounce their ownership to make the liquidity permanently locked.

While the pool is live, the quote token side will continuously accrue interest, because all of the quote token is locked in a yield-bearing Euler vault.
