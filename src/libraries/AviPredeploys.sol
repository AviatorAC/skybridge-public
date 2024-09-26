// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

library AviPredeploys {
    address internal constant L1_STANDARD_BRIDGE = 0xfA6D8Ee5BE770F84FC001D098C4bD604Fe01284a;
    address internal constant L2_STANDARD_BRIDGE = 0x4200000000000000000000000000000000000010;
    address internal constant L1_AVI_STANDARD_BRIDGE = 0xDEfA668c802340Ca48087b49DC9dfe093129BF60;

    // https://docs.optimism.io/chain/addresses
    // TODO: update these to mainnet addresses when time comes
    address internal constant L1_CROSS_DOMAIN_MESSENGER = 0xC34855F4De64F1840e5686e64278da901e261f20;
    address internal constant L2_CROSS_DOMAIN_MESSENGER = 0x4200000000000000000000000000000000000007;
}
