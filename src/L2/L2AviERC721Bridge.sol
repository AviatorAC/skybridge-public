// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { AviERC721Bridge } from "src/universal/AviERC721Bridge.sol";
import { IOptimismMintableERC721 } from "@eth-optimism/contracts-bedrock/src/universal/IOptimismMintableERC721.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

contract L2AviERC721Bridge is AviERC721Bridge {
    string public constant version = "1.2.1";

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(bool isTestMode) {
        // isTestMode is used to disable the disabling of the initializers when running tests
        if (!isTestMode) {
            _disableInitializers();
        }
    }

    function initialize(address _otherBridge) public initializer {
        require(_otherBridge != address(0), "L2AviERC721Bridge: other bridge cannot be address(0)");
        __SkyBridge_init(_otherBridge);
    }

    function paused() public view override returns (bool) { }

    /// @notice Completes an ERC721 bridge from the other domain and sends the ERC721 token to the
    ///         recipient on this domain.
    /// @param _localToken  Address of the ERC721 token on this domain.
    /// @param _remoteToken Address of the ERC721 token on the other domain.
    /// @param _from        Address that triggered the bridge on the other domain.
    /// @param _to          Address to receive the token on this domain.
    /// @param _tokenId     ID of the token being deposited.
    /// @param _extraData   Optional data to forward to L1.
    ///                     Data supplied here will not be used to execute any code on L1 and is
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
        require(_localToken != address(this), "L2AviERC721Bridge: local token cannot be self");
        require(_to != address(0), "L2AviERC721Bridge: cannot transfer to the zero address");

        // Note that supportsInterface makes a callback to the _localToken address which is user
        // provided.
        require(
            ERC165Checker.supportsInterface(_localToken, type(IOptimismMintableERC721).interfaceId),
            "L2AviERC721Bridge: local token interface is not compliant"
        );

        require(
            _remoteToken == IOptimismMintableERC721(_localToken).remoteToken(),
            "L2AviERC721Bridge: wrong remote token for Optimism Mintable ERC721 local token"
        );

        // When a deposit is finalized, we give the NFT with the same tokenId to the account
        // on L2. Note that safeMint makes a callback to the _to address which is user provided.
        IOptimismMintableERC721(_localToken).safeMint(_to, _tokenId);

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
        require(_remoteToken != address(0), "L2AviERC721Bridge: remote token cannot be address(0)");
        require(msg.value == flatFee, "L2AviERC721Bridge: bridging ERC721 must include sufficient ETH value");

        (bool sent, ) = payable(flatFeeRecipient).call{value: msg.value}("");
        require(sent, "L2AviERC721Bridge: failed to send ETH to fee recipient");

        // Check that the withdrawal is being initiated by the NFT owner
        require(
            _from == IOptimismMintableERC721(_localToken).ownerOf(_tokenId),
            "L2AviERC721Bridge: Withdrawal is not being initiated by NFT owner"
        );

        // Construct calldata for l1ERC721Bridge.finalizeBridgeERC721(_to, _tokenId)
        // slither-disable-next-line reentrancy-events
        address remoteToken = IOptimismMintableERC721(_localToken).remoteToken();
        require(remoteToken == _remoteToken, "L2AviERC721Bridge: remote token does not match given value");

        // When a withdrawal is initiated, we burn the withdrawer's NFT to prevent subsequent L2
        // usage
        // slither-disable-next-line reentrancy-events
        IOptimismMintableERC721(_localToken).burn(_from, _tokenId);

        // slither-disable-next-line reentrancy-events
        emit ERC721BridgeInitiated(_localToken, remoteToken, _from, _to, _tokenId, _extraData);
    }
}
