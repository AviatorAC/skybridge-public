// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CrossDomainMessenger } from "@eth-optimism/contracts-bedrock/src/universal/CrossDomainMessenger.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @title ERC721Bridge
/// @notice ERC721Bridge is a base contract for the L1 and L2 ERC721 bridges.
abstract contract AviERC721Bridge is AccessControlUpgradeable {
    address public OTHER_BRIDGE;

    /// @notice Number of admins on the contract.
    uint private _numAdmins;

    /// @notice The address of the receiver of the flat fee. On L1 it's the address on the same chain, while on L2 it's the L1 address
    address public flatFeeRecipient;

    /// @notice The flat bridging fee for all deposits. Measured in ETH.
    uint256 public flatFee;

    /// @notice access control role pauser constant.
    bytes32 public constant PAUSER_ROLE = keccak256("aviator.pauser_role");

    /// @notice access control role backend
    bytes32 public constant BACKEND_ROLE = keccak256("aviator.backend_role");

    /**
     * @dev This gap is used to allow further fields on base contracts without causing possible storage clashes.
     */
    uint256[49] private __gap;

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

    /// @notice Emitted when the Flat Fee is changed.
    /// @param previousFlatFee  uint256 of the previous value.
    /// @param flatFee          uint256 of the new value.
    /// @param executedBy       Address of caller.
    event FlatFeeChanged(
        uint256 previousFlatFee,
        uint256 flatFee,
        address executedBy
    );

    /// @notice Emitted when the Flat Fee Recipient address is changed.
    /// @param previousFlatFeeRecipient     Address of previsous Flat Fee Recipient.
    /// @param flatFeeRecipient             Address of new Flat Fee Recipient.
    /// @param executedBy                   Address of caller.
    event FlatFeeRecipientChanged(
        address previousFlatFeeRecipient,
        address flatFeeRecipient,
        address executedBy
    );

    /// @notice Emitted whenever L2 Bridge is set.
    /// @param previousOtherBridge      address of old L2 Bridge.
    /// @param otherBridge              address of new L2 Bridge.
    /// @param executedBy               address of calling address.
    event OtherBridgeChanged(
        address previousOtherBridge,
        address otherBridge,
        address executedBy
    );

    modifier onlyPauserOrAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(PAUSER_ROLE, msg.sender),
            "AviBridge: function can only be called by pauser or admin role"
        );

        _;
    }

    modifier onlyBackend() {
        require(
            hasRole(BACKEND_ROLE, msg.sender),
            "AviBridge: function can only be called by backend role"
        );

         _;
    }

    /// @param _otherBridge Address of the ERC721 bridge on the other network.
    function __SkyBridge_init(address _otherBridge) public onlyInitializing {
        // This is intentionally disabled: we cannot create an L2 bridge without an L1 bridge, and if the L1 bridge also checks
        // that the provided address for the other bridge is not 0, then we have an infinite loop of failures.
        // Maybe there's better ways, but for now this is the solution. This function is not supposed to be called by anything but
        // (L1/L2)AviERC721Bridge.initialize anyways :shrug:

        // require(_otherBridge != address(0), "AviERC721Bridge: _otherBridge address cannot be zero");

        __AccessControl_init();

        OTHER_BRIDGE = _otherBridge;
        flatFee = 0.002 ether;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); // make the deployer admin
        _numAdmins++;
    }

    /// @notice Updates the the address of the other bridge contract.
    /// @param _otherBridge Address of the other bridge contract.
    function setOtherBridge(address _otherBridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_otherBridge != address(0), "AviBridge: _otherBridge address cannot be zero");
        address _previousBridge = OTHER_BRIDGE;
        OTHER_BRIDGE = _otherBridge;

        emit OtherBridgeChanged(_previousBridge, OTHER_BRIDGE, msg.sender);
    }

    /// @notice Updates the flat fee recipient for all deposits.
    /// @param _recipient New flat fee recipient address
    function setFlatFeeRecipient(address _recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_recipient != address(0), "AviBridge: _recipient address cannot be zero");

        address previousFlatFeeRecipient = flatFeeRecipient;

        flatFeeRecipient = _recipient;

        emit FlatFeeRecipientChanged(previousFlatFeeRecipient, flatFeeRecipient, msg.sender);
    }

    /// @notice Updates the flat fee for all deposits.
    /// @param _fee New flat fee.
    function setFlatFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_fee < 0.005 ether, "AviBridge: _fee must be less than 0.005 ether");
        uint256 previousFee = flatFee;
        flatFee = _fee;
        emit FlatFeeChanged(previousFee, flatFee, msg.sender);
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

    /// @notice Add a new pauser address to the list of pausers.
    /// @param _pauser New Pauser address.
    function addPauser(address _pauser) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!hasRole(PAUSER_ROLE, _pauser), "Pauser already added.");

        _grantRole(PAUSER_ROLE, _pauser);
    }

    /// @notice Remove an pauser from the list of pausers.
    /// @param _pauser Address to remove.
    function removePauser(address _pauser) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(PAUSER_ROLE, _pauser), "Address is not a recognized pauser.");

        _revokeRole(PAUSER_ROLE, _pauser);
    }

    /// @notice Add a new backend address to the list of backends.
    /// @param _backend Address to add as a backend.
    function addBackend(address _backend) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!hasRole(BACKEND_ROLE, _backend), "Backend already added.");

        _grantRole(BACKEND_ROLE, _backend);
    }

    /// @notice Remove an backend from the list of backends.
    /// @param _backend Address to remove as a backend.
    function removeBackend(address _backend) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(BACKEND_ROLE, _backend), "Address is not a recognized backend.");

        _revokeRole(BACKEND_ROLE, _backend);
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

    /// @notice Override renounceRole to disable it.
    function renounceRole(bytes32, address) public pure override {
        revert("AviERC721Bridge: renounceRole is disabled, use removeAdmin to remove yourself as an admin");
    }

    /// @notice Override revokeRole to disable it.
    function revokeRole(bytes32 role, address) public virtual override onlyRole(getRoleAdmin(role)) {
        revert("AviBridge: revokeRole is disabled, use removeAdmin to remove yourself as an admin");
    }
}
