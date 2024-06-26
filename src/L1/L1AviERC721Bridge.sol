// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { AviERC721Bridge } from "src/universal/AviERC721Bridge.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { L2AviERC721Bridge } from "src/L2/L2AviERC721Bridge.sol";
import { ISemver } from "@eth-optimism/contracts-bedrock/src/universal/ISemver.sol";
import { Predeploys } from "@eth-optimism/contracts-bedrock/src/libraries/Predeploys.sol";
import { CrossDomainMessenger } from "@eth-optimism/contracts-bedrock/src/universal/CrossDomainMessenger.sol";
import { Constants } from "@eth-optimism/contracts-bedrock/src/libraries/Constants.sol";
import { SuperchainConfig } from "@eth-optimism/contracts-bedrock/src/L1/SuperchainConfig.sol";
import { LiquidityPool } from "src/L1/LiquidityPool.sol";

/// @title L1ERC721Bridge
/// @notice The L1 ERC721 bridge is a contract which works together with the L2 ERC721 bridge to
///         make it possible to transfer ERC721 tokens from Ethereum to Optimism. This contract
///         acts as an escrow for ERC721 tokens deposited into L2.
contract L1AviERC721Bridge is AviERC721Bridge, ISemver {
    /// @notice Mapping of L1 token to L2 token to ID to boolean, indicating if the given L1 token
    ///         by ID was deposited for a given L2 token.
    mapping(address => mapping(address => mapping(uint256 => bool))) public deposits;

    /// @notice Address of the SuperchainConfig contract.
    SuperchainConfig public superchainConfig;

    /// @notice The flat bridging fee for all deposits. Measured in ETH.
    uint256 public flatFee = 0.002 ether;

    /// @notice the liquidity pool
    LiquidityPool public LIQUIDITY_POOL;

    /// @notice Semantic version.
    /// @custom:semver 2.0.0
    string public constant version = "2.0.0";

    /// @notice Constructs the L1ERC721Bridge contract.
    constructor(address payable _liquidityPool) AviERC721Bridge(address(0)) {
        superchainConfig = SuperchainConfig(address(0));
        LIQUIDITY_POOL = LiquidityPool(_liquidityPool);
    }

    /// @notice Updates the flat fee for all deposits.
    /// @param _fee New flat fee.
    function setFlatFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_fee < 0.005 ether, "AviBridge: _fee must be less than 0.005 ether");
        flatFee = _fee;
    }

    /// @inheritdoc AviERC721Bridge
    function paused() public view override returns (bool) {
        return superchainConfig.paused();
    }

    /// @notice Updates the the address of the other bridge contract.
    /// @param _otherBridge Address of the other bridge contract.
    function setOtherBridge(address _otherBridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        OTHER_BRIDGE = _otherBridge;
    }

    /// @notice Completes an ERC721 bridge from the other domain and sends the ERC721 token to the
    ///         recipient on this domain.
    /// @param _localToken  Address of the ERC721 token on this domain.
    /// @param _remoteToken Address of the ERC721 token on the other domain.
    /// @param _from        Address that triggered the bridge on the other domain.
    /// @param _to          Address to receive the token on this domain.
    /// @param _tokenId     ID of the token being deposited.
    /// @param _extraData   Optional data to forward to L2.
    ///                     Data supplied here will not be used to execute any code on L2 and is
    ///                     only emitted as extra data for the convenience of off-chain tooling.
    function finalizeBridgeERC721(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _tokenId,
        bytes calldata _extraData
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(paused() == false, "L1ERC721Bridge: paused");
        require(_localToken != address(this), "L1ERC721Bridge: local token cannot be self");

        // Checks that the L1/L2 NFT pair has a token ID that is escrowed in the L1 Bridge.
        require(
            deposits[_localToken][_remoteToken][_tokenId] == true,
            "L1ERC721Bridge: Token ID is not escrowed in the L1 Bridge"
        );

        // Mark that the token ID for this L1/L2 token pair is no longer escrowed in the L1
        // Bridge.
        deposits[_localToken][_remoteToken][_tokenId] = false;

        // When a withdrawal is finalized on L1, the L1 Bridge transfers the NFT to the
        // withdrawer.
        IERC721(_localToken).safeTransferFrom(address(this), _to, _tokenId);

        // slither-disable-next-line reentrancy-events
        emit ERC721BridgeFinalized(_localToken, _remoteToken, _from, _to, _tokenId, _extraData);
    }

    /// @inheritdoc AviERC721Bridge
    function _initiateBridgeERC721(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _tokenId,
        bytes calldata _extraData
    )
        internal
        override
    {
        require(_remoteToken != address(0), "L1ERC721Bridge: remote token cannot be address(0)");
        require(msg.value == flatFee, "L1ERC721Bridge: bridging ERC721 must include sufficient ETH value");

        (bool sent, ) = payable(LIQUIDITY_POOL).call{value: msg.value}("");
        require(sent, "L1ERC721Bridge: failed to send ETH to liquidity pool");

        // Lock token into bridge
        deposits[_localToken][_remoteToken][_tokenId] = true;
        IERC721(_localToken).transferFrom(_from, address(this), _tokenId);

        // Send calldata into L2
        emit ERC721BridgeInitiated(_localToken, _remoteToken, _from, _to, _tokenId, _extraData);
    }
}
