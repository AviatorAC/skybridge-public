// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from 'forge-std/Test.sol';
import { IOptimismMintableERC20, ILegacyMintableERC20 } from "@eth-optimism/contracts-bedrock/src/universal/IOptimismMintableERC20.sol";
import { IOptimismMintableERC721 } from "@eth-optimism/contracts-bedrock/src/universal/IOptimismMintableERC721.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { AviPredeploys } from "src/libraries/AviPredeploys.sol";

import "forge-std/console2.sol";

contract LegacyMintable is ILegacyMintableERC20, ERC20 {
    address public otherToken;

    constructor(address _otherToken) ERC20("LegacyMintable", "LM") {
        otherToken = _otherToken;
    }

    function l1Token() external view override returns (address) {
        return otherToken;
    }

    function mint(address _to, uint256 _amount) external override {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external override {
        _burn(_from, _amount);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        bytes4 iface1 = type(IERC165).interfaceId;
        // Interface corresponding to the legacy L2StandardERC20.
        bytes4 iface2 = type(ILegacyMintableERC20).interfaceId;

        return interfaceId == iface1 || interfaceId == iface2;
    }

    function test() public virtual {}
}

contract NewMintable is IOptimismMintableERC20, ERC20 {
    address public otherToken;
    address public BRIDGE;

    constructor(address _otherToken, address _bridge) ERC20("NewMintable", "NM") {
        otherToken = _otherToken;
        BRIDGE = _bridge;
    }

    function remoteToken() external view override returns (address) {
        return otherToken;
    }

    function bridge() external view override returns (address) {
        return BRIDGE;
    }

    function mint(address _to, uint256 _amount) external override {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external override {
        _burn(_from, _amount);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        bytes4 iface1 = type(IERC165).interfaceId;
        // Interface corresponding to the updated OptimismMintableERC20 (this contract).
        bytes4 iface3 = type(IOptimismMintableERC20).interfaceId;

        return interfaceId == iface1 || interfaceId == iface3;
    }

    function test() public virtual {}
}

contract OptimismNFT is IOptimismMintableERC721, ERC721Enumerable {
    address public internalBridge;
    address public internalRemoteToken;

    constructor(
        address _bridge,
        address _remoteToken
    ) ERC721("Mintable NFT", "MNFT") {
        internalBridge = _bridge;
        internalRemoteToken = _remoteToken;
    }

    function test() public virtual {}

    function safeMint(address _to, uint256 _tokenId) external override {
        _safeMint(_to, _tokenId);
    }

    function burn(address _from, uint256 _tokenId) external override {
        _burn(_tokenId);

        emit Burn(_from, _tokenId);
    }

    function REMOTE_CHAIN_ID() external pure override returns (uint256) {
        return 1337;
    }

    function REMOTE_TOKEN() external view override returns (address) {
        return internalRemoteToken;
    }

    function BRIDGE() external view override returns (address) {
        return internalBridge;
    }

    function remoteChainId() external pure override returns (uint256) {
        return 1337;
    }

    function remoteToken() external view override returns (address) {
        return internalRemoteToken;
    }

    function bridge() external view override returns (address) {
        return internalBridge;
    }

    function supportsInterface(bytes4 _interfaceId) public view override(ERC721Enumerable, IERC165) returns (bool) {
        bytes4 iface = type(IOptimismMintableERC721).interfaceId;
        return _interfaceId == iface || super.supportsInterface(_interfaceId);
    }
}

contract OptimismMintables is Test {
    address public legacyL1;
    address public legacyL2;

    address public newL1;
    address public newL2;

    LegacyMintable public legacyL1Contract;
    LegacyMintable public legacyL2Contract;

    NewMintable public newL1Contract;
    NewMintable public newL2Contract;

    address public nftL1;
    address public nftL2;

    OptimismNFT public nftL1Contract;
    OptimismNFT public nftL2Contract;

    constructor() {
        legacyL1 = makeAddr("legacyL1");
        legacyL2 = makeAddr("legacyL2");

        newL1 = makeAddr("newL1");
        newL2 = makeAddr("newL2");

        nftL1 = makeAddr("nftL1");
        nftL2 = makeAddr("nftL2");

        legacyL1Contract = LegacyMintable(legacyL1);

        deployCodeTo(
            "OptimismMintables.sol:LegacyMintable",
            abi.encode(legacyL2),
            legacyL1
        );

        legacyL2Contract = LegacyMintable(legacyL2);

        deployCodeTo(
            "OptimismMintables.sol:LegacyMintable",
            abi.encode(legacyL1),
            legacyL2
        );

        newL1Contract = NewMintable(newL1);

        deployCodeTo(
            "OptimismMintables.sol:NewMintable",
            abi.encode(newL2, AviPredeploys.L2_STANDARD_BRIDGE),
            newL1
        );

        newL2Contract = NewMintable(newL2);

        deployCodeTo(
            "OptimismMintables.sol:NewMintable",
            abi.encode(newL1, AviPredeploys.L1_STANDARD_BRIDGE),
            newL2
        );

        nftL1Contract = OptimismNFT(nftL1);

        deployCodeTo(
            "OptimismMintables.sol:OptimismNFT",
            abi.encode(AviPredeploys.L1_STANDARD_BRIDGE, nftL2),
            nftL1
        );

        nftL2Contract = OptimismNFT(nftL2);

        deployCodeTo(
            "OptimismMintables.sol:OptimismNFT",
            abi.encode(AviPredeploys.L2_STANDARD_BRIDGE, nftL1),
            nftL2
        );
    }

    function test() public virtual {}
}
