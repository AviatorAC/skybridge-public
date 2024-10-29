// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// This file is a 1:1 clone from Optimism's file, excluding the IERC721Enumerable extension for the interface.
// We need this as we have "upgradeable" mintable tokens (mostly just for the interface since we cannot call the constructor in the way we do deploys)

/// @title IOptimismMintableERC721
/// @notice Interface for contracts that are compatible with the OptimismMintableERC721 standard.
///         Tokens that follow this standard can be easily transferred across the ERC721 bridge.
interface IOptimismMintableERC721Avi {
    /// @notice Emitted when a token is minted.
    /// @param account Address of the account the token was minted to.
    /// @param tokenId Token ID of the minted token.
    event Mint(address indexed account, uint256 tokenId);

    /// @notice Emitted when a token is burned.
    /// @param account Address of the account the token was burned from.
    /// @param tokenId Token ID of the burned token.
    event Burn(address indexed account, uint256 tokenId);

    /// @notice Mints some token ID for a user, checking first that contract recipients
    ///         are aware of the ERC721 protocol to prevent tokens from being forever locked.
    /// @param _to      Address of the user to mint the token for.
    /// @param _tokenId Token ID to mint.
    function safeMint(address _to, uint256 _tokenId) external;

    /// @notice Burns a token ID from a user.
    /// @param _from    Address of the user to burn the token from.
    /// @param _tokenId Token ID to burn.
    function burn(address _from, uint256 _tokenId) external;

    /// @notice Chain ID of the chain where the remote token is deployed.
    function REMOTE_CHAIN_ID() external view returns (uint256);

    /// @notice Address of the token on the remote domain.
    function REMOTE_TOKEN() external view returns (address);

    /// @notice Address of the ERC721 bridge on this network.
    function BRIDGE() external view returns (address);

    /// @notice Chain ID of the chain where the remote token is deployed.
    function remoteChainId() external view returns (uint256);

    /// @notice Address of the token on the remote domain.
    function remoteToken() external view returns (address);

    /// @notice Address of the ERC721 bridge on this network.
    function bridge() external view returns (address);
}
