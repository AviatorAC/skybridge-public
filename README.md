# AVI SkyBridge

The SkyBridge contracts! Meet the bridges, the liquidity pool, and our mintable tokens!

# Known Possible Issues

Here is a list of _possible_ issues that we are aware of at this time, and will result in your report being closed if reported:

- SkyBridge tokens not trying to call `_spendAllowance()` when bridge calls `burn()` for a user's tokens
  - We are investigating if this is a requirement or not, considering this function is only ever called when bridging tokens
- `finalize*` functions can be affected by the bridge being paused, causing the bridging to never finish
  - We are discussing internally if this is something that should be dropped
- The fee recipient in L1 bridges defaults to the Liquidity Pool, instead of being provided when initializing the contract
  - We are discussing internally if this is something that should be changed, or if it is ok to have as a sane default
- `_numAdmin` not being properly tracked in all contracts when upgrading
  - Note: We don't actually know if this is an issue, but it is something we are looking into and testing out!

## How to run tests yourself

1. Install git, foundry, and node.js (we recommend using volta to manage node.js versions, but you can also use fnm, nvm, or just direct install)
1. Clone this repository
1. Enable corepack: `npx corepack enable`
1. Install dependencies: `yarn`
1. Run tests: `yarn test`
