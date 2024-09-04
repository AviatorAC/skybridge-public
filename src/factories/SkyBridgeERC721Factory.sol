// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { SkyBridgeERC721 } from "./SkyBridgeERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title OptimismMintableERC721Factory
/// @notice Factory contract for creating OptimismMintableERC721 contracts.
contract SkyBridgeERC721Factory is Ownable {
    /// @notice Address of the ERC721 bridge on this network.
    address public immutable BRIDGE;

    /// @notice Chain ID for the remote network.
    uint256 public immutable REMOTE_CHAIN_ID;

    /**
    * @dev Emitted when a remote token address is zero.
    */
    error RemoteTokenCannotBeZeroAddress();

    /**
     * @dev Emitted when the bridge address provided is the zero address.
     */
    error BridgeAddressCannotBeZero();

    /**
     * @dev Emitted when the flat fee recipient address is the zero address.
     */
    error FlatFeeRecipientCannotBeZero();

    /// @notice The flat bridging fee for all deposits. Measured in ETH.
    uint256 public flatFee = 0.005 ether;

    /// @notice The address of the receiver of the flat fee.
    address public flatFeeRecipient;

    /// @notice Emitted whenever a new OptimismMintableERC721 contract is created.
    /// @param localToken  Address of the token on the this domain.
    /// @param remoteToken Address of the token on the remote domain.
    /// @param deployer    Address of the initiator of the deployment
    event SkyBridgeERC721Created(address indexed localToken, address indexed remoteToken, address deployer);

    /// @notice Emitted when an the flat fee is changed.
    /// @param previousFlatFee   Previous flat fee.
    /// @param newFlatFee        New flat fee.
    /// @param executedBy        Address of caller.
    event FlatFeeChanged(uint256 previousFlatFee, uint256 newFlatFee, address executedBy);

    /// @notice Emitted when the Flat Fee Recipient address is changed.
    /// @param previousFlatFeeRecipient     Address of previsous Flat Fee Recipient.
    /// @param flatFeeRecipient             Address of new Flat Fee Recipient.
    /// @param executedBy                   Address of caller.
    event FlatFeeRecipientChanged(
        address previousFlatFeeRecipient,
        address flatFeeRecipient,
        address executedBy
    );

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice The semver MUST be bumped any time that there is a change in
    ///         the OptimismMintableERC721 token contract since this contract
    ///         is responsible for deploying OptimismMintableERC721 contracts.
    /// @param _bridge Address of the ERC721 bridge on this network.
    /// @param _remoteChainId Chain ID for the remote network.
    /// @param _flatFeeRecipient Address of the receiver of the flat fee.
    constructor(address _bridge, uint256 _remoteChainId, address _flatFeeRecipient) {
        if (_bridge == address(0)) revert BridgeAddressCannotBeZero();
        if (_flatFeeRecipient == address(0)) revert FlatFeeRecipientCannotBeZero();

        BRIDGE = _bridge;
        REMOTE_CHAIN_ID = _remoteChainId;
        flatFeeRecipient = _flatFeeRecipient;
    }

    /// @notice Updates the flat fee recipient for deploys.
    /// @param _recipient New flat fee recipient address
    function setFlatFeeRecipient(address _recipient) public onlyOwner {
        require(_recipient != address(0), "_recipient address cannot be zero");

        address previousFlatFeeRecipient = flatFeeRecipient;

        flatFeeRecipient = _recipient;

        emit FlatFeeRecipientChanged(previousFlatFeeRecipient, flatFeeRecipient, msg.sender);
    }

    /// @notice Updates the flat fee for deploys.
    /// @param _fee New flat fee.
    function setFlatFee(uint256 _fee) external onlyOwner {
        require(_fee <= 0.005 ether, "_fee must be less or equal with 0.005 ether");

        uint256 previousFlatFee = flatFee;

        flatFee = _fee;

        emit FlatFeeChanged(previousFlatFee, flatFee, msg.sender);
    }

    /// @notice Creates an instance of the standard ERC721.
    /// @param _remoteToken Address of the corresponding token on the other domain.
    /// @param _name        ERC721 name.
    /// @param _symbol      ERC721 symbol.
    function createSkyBridgeERC721(
        address _remoteToken,
        string memory _name,
        string memory _symbol
    ) external payable returns (address) {
        if (_remoteToken == address(0)) {
            revert RemoteTokenCannotBeZeroAddress();
        }

        require(msg.value == flatFee, "SkyBridge: incorrect flat fee sent");

        (bool sentToFlatFee, ) = payable(flatFeeRecipient).call{value: flatFee}("");
        require(sentToFlatFee, "SkyBridge: transfer of flat fee failed");

        // deploy clone
        bytes32 salt = keccak256(abi.encode(REMOTE_CHAIN_ID, _remoteToken, _name, _symbol));
        address newSkybridgeERC721 = address(new SkyBridgeERC721{ salt: salt }(BRIDGE, REMOTE_CHAIN_ID, _remoteToken, _name, _symbol));

        emit SkyBridgeERC721Created(newSkybridgeERC721, _remoteToken, msg.sender);

        return newSkybridgeERC721;
    }
}
