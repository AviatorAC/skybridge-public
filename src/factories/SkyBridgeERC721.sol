// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ERC721EnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IOptimismMintableERC721 } from "@eth-optimism/contracts-bedrock/src/universal/IOptimismMintableERC721.sol";
import { IOptimismMintableERC721Avi } from "./IOptimismMintableERC721Avi.sol";
import { SkyBridgeERC721Factory } from "./SkyBridgeERC721Factory.sol";

/// @title OptimismMintableERC721
/// @notice This contract is the remote representation for some token that lives on another network,
///         typically an Optimism representation of an Ethereum-based token. Standard reference
///         implementation that can be extended or modified according to your needs.
contract SkyBridgeERC721 is ERC721EnumerableUpgradeable, IOptimismMintableERC721Avi {
    string public constant version = "1.0.0";

    /// @inheritdoc IOptimismMintableERC721Avi
    uint256 public REMOTE_CHAIN_ID;

    /// @inheritdoc IOptimismMintableERC721Avi
    address public REMOTE_TOKEN;

    /// @inheritdoc IOptimismMintableERC721Avi
    address public immutable BRIDGE;

    /// @notice Admin factory address
    SkyBridgeERC721Factory public immutable FACTORY;

    /// @notice Base token URI for this token.
    string public baseTokenURI;

    constructor(
        address _bridge,
        address _factory
    ) {
        require(_bridge != address(0), "SkyBridgeERC721: bridge cannot be address(0)");

        BRIDGE = _bridge;
        FACTORY = SkyBridgeERC721Factory(_factory);
    }

    /// @param _remoteChainId Chain ID where the remote token is deployed.
    /// @param _remoteToken   Address of the corresponding token on the other network.
    /// @param _name          ERC721 name.
    /// @param _symbol        ERC721 symbol.
    function initialize(
        uint256 _remoteChainId,
        address _remoteToken,
        string memory _name,
        string memory _symbol
    ) public onlyFactory initializer {
        require(_remoteChainId != 0, "SkyBridgeERC721: remote chain id cannot be zero");
        require(_remoteToken != address(0), "SkyBridgeERC721: remote token cannot be address(0)");

        __ERC721_init(_name, _symbol);

        REMOTE_CHAIN_ID = _remoteChainId;
        REMOTE_TOKEN = _remoteToken;

        // Creates a base URI in the format specified by EIP-681:
        // https://eips.ethereum.org/EIPS/eip-681
        baseTokenURI = string(
            abi.encodePacked(
                "ethereum:",
                Strings.toHexString(uint160(_remoteToken), 20),
                "@",
                Strings.toString(_remoteChainId),
                "/tokenURI?uint256="
            )
        );
    }

    modifier onlyFactory() {
        require(msg.sender == address(FACTORY), "SkyBridgeERC721: Only the factory can call this function");
        _;
    }

    /// @inheritdoc IOptimismMintableERC721Avi
    function remoteChainId() external view returns (uint256) {
        return REMOTE_CHAIN_ID;
    }

    /// @inheritdoc IOptimismMintableERC721Avi
    function remoteToken() external view returns (address) {
        return REMOTE_TOKEN;
    }

    /// @inheritdoc IOptimismMintableERC721Avi
    function bridge() external view returns (address) {
        return BRIDGE;
    }

    /// @inheritdoc IOptimismMintableERC721Avi
    function safeMint(address _to, uint256 _tokenId) external onlyAuthorizedBridge {
        _safeMint(_to, _tokenId);

        emit Mint(_to, _tokenId);
    }

    /// @inheritdoc IOptimismMintableERC721Avi
    function burn(address _from, uint256 _tokenId) external onlyAuthorizedBridge {
        _burn(_tokenId);

        emit Burn(_from, _tokenId);
    }

    /**
     * @notice Modifier to check if the caller is an authorized bridge via the factory.
         */
    modifier onlyAuthorizedBridge() {
        require(FACTORY.isAuthorizedBridge(msg.sender), "SkyBridge: only authorized bridges can mint/burn");
        _;
    }

    /// @notice Returns the base token URI.
    /// @return Base token URI.
    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    /// @notice Checks if a given interface ID is supported by this contract.
    /// @param _interfaceId The interface ID to check.
    /// @return True if the interface ID is supported, false otherwise.
    function supportsInterface(bytes4 _interfaceId) public view override(ERC721EnumerableUpgradeable) returns (bool) {
        // Lie that we implement the actual optimism interface because they for some reason extend `IERC721Enumerable`, and we cannot make this stuff upgradeable
        bytes4 iface = type(IOptimismMintableERC721).interfaceId;
        return _interfaceId == iface || super.supportsInterface(_interfaceId);
    }
}
