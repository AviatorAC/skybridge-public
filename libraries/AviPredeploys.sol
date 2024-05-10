// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library AviPredeploys {
    address internal constant L1_STANDARD_BRIDGE = 0xfA6D8Ee5BE770F84FC001D098C4bD604Fe01284a;
    address internal constant L2_STANDARD_BRIDGE = 0x4200000000000000000000000000000000000010;
    address internal constant L1_AVI_STANDARD_BRIDGE = 0xDEfA668c802340Ca48087b49DC9dfe093129BF60;

    // https://docs.optimism.io/chain/addresses
    address internal constant L1_CROSS_DOMAIN_MESSENGER = 0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef;
    address internal constant L2_CROSS_DOMAIN_MESSENGER = 0x4200000000000000000000000000000000000007;
}
