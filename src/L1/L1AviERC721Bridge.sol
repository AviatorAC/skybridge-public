// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { AviERC721Bridge } from "src/universal/AviERC721Bridge.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { L2AviERC721Bridge } from "src/L2/L2AviERC721Bridge.sol";
import { CrossDomainMessenger } from "@eth-optimism/contracts-bedrock/src/universal/CrossDomainMessenger.sol";
import { LiquidityPool } from "src/L1/LiquidityPool.sol";

/// @title L1AviERC721Bridge
/// @notice The L1 ERC721 bridge is a contract which works together with the L2 ERC721 bridge to
///         make it possible to transfer ERC721 tokens from Ethereum to Optimism. This contract
///         acts as an escrow for ERC721 tokens deposited into L2.
contract L1AviERC721Bridge is AviERC721Bridge {
    /// @notice Mapping of L1 token to L2 token to ID to boolean, indicating if the given L1 token
    ///         by ID was deposited for a given L2 token.
    mapping(address => mapping(address => mapping(uint256 => bool))) public deposits;

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.2.0";

    bool internal _isPaused;

    /// @notice Emitted whenever bridge paused value is set.
    /// @param paused        bool of paused value.
    /// @param executedBy    address of calling address.
    event PausedChanged(
        bool    paused,
        address executedBy
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(bool isTestMode) {
        // isTestMode is used to disable the disabling of the initializers when running tests
        if (!isTestMode) {
            _disableInitializers();
        }
    }

    /// @notice Constructs the L1AviERC721Bridge contract.
    /// @param _l1FlatFeeRecipient Address of the flatFeeRecipient.
    function initialize(address payable _l1FlatFeeRecipient) public initializer {
        require(_l1FlatFeeRecipient != address(0), 'L1AviERC721Bridge: _l1FlatFeeRecipient cant be zero address');

        __SkyBridge_init(address(0));

        flatFeeRecipient = _l1FlatFeeRecipient;
        _isPaused = true;
    }

    /// @inheritdoc AviERC721Bridge
    function paused() public view override returns (bool) {
        return _isPaused;
    }

    /// @notice Updates the paused status of the bridge
    /// @param _paused New paused status
    function setPaused(bool _paused) external onlyPauserOrAdmin {
        _isPaused = _paused;
        emit PausedChanged(_isPaused, msg.sender);
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
        onlyBackend
    {
        require(_localToken != address(this), "L1AviERC721Bridge: local token cannot be self");
        require(_to != address(0), "L1AviERC721Bridge: cannot transfer to the zero address");
        // Checks that the L1/L2 NFT pair has a token ID that is escrowed in the L1 Bridge.
        require(
            deposits[_localToken][_remoteToken][_tokenId] == true,
            "L1AviERC721Bridge: Token ID is not escrowed in the L1 Bridge"
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
        require(paused() == false, "L1AviERC721Bridge: paused");
        require(_remoteToken != address(0), "L1AviERC721Bridge: remote token cannot be address(0)");
        require(msg.value == flatFee, "L1AviERC721Bridge: bridging ERC721 must include sufficient ETH value");

        (bool sent, ) = payable(flatFeeRecipient).call{value: msg.value}("");
        require(sent, "L1AviERC721Bridge: failed to send ETH to fee recipient");

        // Lock token into bridge
        deposits[_localToken][_remoteToken][_tokenId] = true;
        IERC721(_localToken).transferFrom(_from, address(this), _tokenId);

        // Send calldata into L2
        emit ERC721BridgeInitiated(_localToken, _remoteToken, _from, _to, _tokenId, _extraData);
    }
}
