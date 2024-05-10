// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CrossDomainMessenger } from "@eth-optimism/contracts-bedrock/src/universal/CrossDomainMessenger.sol";
import { SuperchainConfig } from "@eth-optimism/contracts-bedrock/src/L1/SuperchainConfig.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ERC721Bridge
/// @notice ERC721Bridge is a base contract for the L1 and L2 ERC721 bridges.
abstract contract AviERC721Bridge is AccessControl {
    /// @notice Address of the bridge on the other network. This will be removed in the
    ///         future, use `otherBridge` instead.
    /// @custom:legacy
    address public OTHER_BRIDGE;
    
    /// @notice Number of admins on the contract.
    uint private _numAdmins = 0;

    /// @notice Emitted when an ERC721 bridge to the other network is initiated.
    /// @param localToken  Address of the token on this domain.
    /// @param remoteToken Address of the token on the remote domain.
    /// @param from        Address that initiated bridging action.
    /// @param to          Address to receive the token.
    /// @param tokenId     ID of the specific token deposited.
    /// @param extraData   Extra data for use on the client-side.
    event ERC721BridgeInitiated(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 tokenId,
        bytes extraData
    );

    /// @notice Emitted when an ERC721 bridge from the other network is finalized.
    /// @param localToken  Address of the token on this domain.
    /// @param remoteToken Address of the token on the remote domain.
    /// @param from        Address that initiated bridging action.
    /// @param to          Address to receive the token.
    /// @param tokenId     ID of the specific token deposited.
    /// @param extraData   Extra data for use on the client-side.
    event ERC721BridgeFinalized(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 tokenId,
        bytes extraData
    );

    /// @param _otherBridge Address of the ERC721 bridge on the other network.
    constructor(address _otherBridge) {
        OTHER_BRIDGE = _otherBridge;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); // make the deployer admin
        _numAdmins++;
    }
    
    /// @notice Add a new admin address to the list of admins.
    /// @param _admin New admin address.
    function addAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!hasRole(DEFAULT_ADMIN_ROLE, _admin), "Admin already added.");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _numAdmins++;
    }

    /// @notice Remove an admin from the list of admins.
    /// @param _admin Address to remove.
    function removeAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(DEFAULT_ADMIN_ROLE, _admin), "Address is not a recognized admin.");
        require (_numAdmins > 1, "Cannot remove the only admin.");

        _revokeRole(DEFAULT_ADMIN_ROLE, _admin);
        _numAdmins--;
    }


    /// @notice Legacy getter for other bridge address.
    /// @return Address of the bridge on the other network.
    function otherBridge() external view returns (address) {
        return OTHER_BRIDGE;
    }

    /// @notice This function should return true if the contract is paused.
    ///         On L1 this function will check the SuperchainConfig for its paused status.
    ///         On L2 this function should be a no-op.
    /// @return Whether or not the contract is paused.
    function paused() public view virtual returns (bool);

    /// @notice Initiates a bridge of an NFT to the caller's account on the other chain. Note that
    ///         this function can only be called by EOAs. Smart contract wallets should use the
    ///         `bridgeERC721To` function after ensuring that the recipient address on the remote
    ///         chain exists. Also note that the current owner of the token on this chain must
    ///         approve this contract to operate the NFT before it can be bridged.
    ///         **WARNING**: Do not bridge an ERC721 that was originally deployed on Optimism. This
    ///         bridge only supports ERC721s originally deployed on Ethereum. Users will need to
    ///         wait for the one-week challenge period to elapse before their Optimism-native NFT
    ///         can be refunded on L2.
    /// @param _localToken  Address of the ERC721 on this domain.
    /// @param _remoteToken Address of the ERC721 on the remote domain.
    /// @param _tokenId     Token ID to bridge.
    /// @param _extraData   Optional data to forward to the other chain. Data supplied here will not
    ///                     be used to execute any code on the other chain and is only emitted as
    ///                     extra data for the convenience of off-chain tooling.
    function bridgeERC721(
        address _localToken,
        address _remoteToken,
        uint256 _tokenId,
        bytes calldata _extraData
    )
        external
        payable
    {
        // Modifier requiring sender to be EOA. This prevents against a user error that would occur
        // if the sender is a smart contract wallet that has a different address on the remote chain
        // (or doesn't have an address on the remote chain at all). The user would fail to receive
        // the NFT if they use this function because it sends the NFT to the same address as the
        // caller. This check could be bypassed by a malicious contract via initcode, but it takes
        // care of the user error we want to avoid.
        require(!Address.isContract(msg.sender), "ERC721Bridge: account is not externally owned");

        _initiateBridgeERC721(_localToken, _remoteToken, msg.sender, msg.sender, _tokenId, _extraData);
    }

    /// @notice Initiates a bridge of an NFT to some recipient's account on the other chain. Note
    ///         that the current owner of the token on this chain must approve this contract to
    ///         operate the NFT before it can be bridged.
    ///         **WARNING**: Do not bridge an ERC721 that was originally deployed on Optimism. This
    ///         bridge only supports ERC721s originally deployed on Ethereum. Users will need to
    ///         wait for the one-week challenge period to elapse before their Optimism-native NFT
    ///         can be refunded on L2.
    /// @param _localToken  Address of the ERC721 on this domain.
    /// @param _remoteToken Address of the ERC721 on the remote domain.
    /// @param _to          Address to receive the token on the other domain.
    /// @param _tokenId     Token ID to bridge.
    /// @param _extraData   Optional data to forward to the other chain. Data supplied here will not
    ///                     be used to execute any code on the other chain and is only emitted as
    ///                     extra data for the convenience of off-chain tooling.
    function bridgeERC721To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _tokenId,
        bytes calldata _extraData
    )
        external
        payable
    {
        require(_to != address(0), "ERC721Bridge: nft recipient cannot be address(0)");

        _initiateBridgeERC721(_localToken, _remoteToken, msg.sender, _to, _tokenId, _extraData);
    }

    /// @notice Internal function for initiating a token bridge to the other domain.
    /// @param _localToken  Address of the ERC721 on this domain.
    /// @param _remoteToken Address of the ERC721 on the remote domain.
    /// @param _from        Address of the sender on this domain.
    /// @param _to          Address to receive the token on the other domain.
    /// @param _tokenId     Token ID to bridge.
    /// @param _extraData   Optional data to forward to the other domain. Data supplied here will
    ///                     not be used to execute any code on the other domain and is only emitted
    ///                     as extra data for the convenience of off-chain tooling.
    function _initiateBridgeERC721(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _tokenId,
        bytes calldata _extraData
    )
        internal
        virtual;
}
