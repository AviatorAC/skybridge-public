// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { SkyBridgeERC721 } from "./SkyBridgeERC721.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @title OptimismMintableERC721Factory
/// @notice Factory contract for creating OptimismMintableERC721 contracts.
contract SkyBridgeERC721Factory is AccessControlUpgradeable {
    /// @notice Address of the ERC721 bridge on this network.
    address public BRIDGE;

    /// @notice Number of admins on the contract.
    uint256 private _numAdmins;

    /// @notice Chain ID for the remote network.
    uint256 public REMOTE_CHAIN_ID;

    // Mapping of each token to its authorized bridges
    mapping(address => bool) public tokenBridgeAuthorization;

    /// @notice The flat bridging fee for all deposits. Measured in ETH.
    uint256 public flatFee;

    /// @notice The address of the receiver of the flat fee.
    address public flatFeeRecipient;

    /// @notice Emitted whenever a new OptimismMintableERC721 contract is created.
    /// @param remoteToken  Address of the token on the remote domain.
    /// @param localToken   Address of the token on the this domain.
    /// @param name         Name of the token.
    /// @param symbol       Symbol of the token.
    /// @param deployer     Address of the initiator of the deployment
    event SkyBridgeERC721Created(
        address indexed remoteToken,
        address indexed localToken,
        string name,
        string symbol,
        address deployer
    );

    event BridgeAuthorizationUpdated(
        address indexed bridge,
        bool authorized,
        address executedBy
    );

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(bool isTestMode) {
        // isTestMode is used to disable the disabling of the initializers when running tests
        if (!isTestMode) {
            _disableInitializers();
        }
    }

    /// @param _bridge Address of the ERC721 bridge on this network.
    /// @param _remoteChainId Chain ID for the remote network.
    /// @param _flatFeeRecipient Address of the receiver of the flat fee.
    function initialize(address _bridge, address _flatFeeRecipient, uint256 _remoteChainId) public initializer {
        __AccessControl_init();

        require(_bridge != address(0), "Bridge cannot be zero address");
        require(_flatFeeRecipient != address(0), "Fee recipient cannot be zero address");

        BRIDGE = _bridge;
        REMOTE_CHAIN_ID = _remoteChainId;

        flatFee = 0.005 ether;
        flatFeeRecipient = _flatFeeRecipient;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); // make the deployer admin
        _numAdmins = 1;

        tokenBridgeAuthorization[_bridge] = true;
        emit BridgeAuthorizationUpdated(_bridge, true, msg.sender);
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

    /// @notice Updates the flat fee recipient for deploys.
    /// @param _recipient New flat fee recipient address
    function setFlatFeeRecipient(address _recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_recipient != address(0), "_recipient address cannot be zero");

        address previousFlatFeeRecipient = flatFeeRecipient;

        flatFeeRecipient = _recipient;

        emit FlatFeeRecipientChanged(previousFlatFeeRecipient, flatFeeRecipient, msg.sender);
    }

    /// @notice Updates the flat fee for deploys.
    /// @param _fee New flat fee.
    function setFlatFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
        require(_remoteToken != address(0), "SkyBridgeERC721Factory: Remote token cannot be zero address");

        require(msg.value == flatFee, "SkyBridgeERC721Factory: incorrect flat fee sent");
        (bool sentToFlatFee, ) = payable(flatFeeRecipient).call{value: flatFee}("");
        require(sentToFlatFee, "SkyBridgeERC721Factory: transfer of flat fee failed");

        // Deploy new token
        bytes32 salt = keccak256(abi.encode(_remoteToken, _name, _symbol));

        // Try to create a new token with the parameters given (only the factory can call initialize, and it can only be called once)
        SkyBridgeERC721 newSkybridgeERC721 = new SkyBridgeERC721{ salt: salt }(BRIDGE, address(this));
        newSkybridgeERC721.initialize(REMOTE_CHAIN_ID, _remoteToken, _name, _symbol);

        emit SkyBridgeERC721Created(_remoteToken, address(newSkybridgeERC721), _name, _symbol, msg.sender);

        return address(newSkybridgeERC721);
    }

    /**
    * @notice Adds or removes a bridge authorization.
     * Can only be called by the admin.
     * @param _bridge The bridge address to be added or removed.
     * @param _authorized Boolean to add (true) or remove (false) the authorization.
    */
    function setBridgeAuthorization(address _bridge, bool _authorized) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_bridge != address(0), "SkyBridgeERC721Factory: Bridge address cannot be zero");

        tokenBridgeAuthorization[_bridge] = _authorized;

        emit BridgeAuthorizationUpdated(_bridge, _authorized, msg.sender);
    }

    /**
     * @notice Checks if a bridge is authorized.
     * @param _bridge The bridge address.
     * @return True if the bridge is authorized, false otherwise.
    */
    function isAuthorizedBridge(address _bridge) external view returns (bool) {
        return tokenBridgeAuthorization[_bridge];
    }

    /// @notice Override renounceRole to disable it.
    function renounceRole(bytes32, address) public pure override {
        revert("SkyBridgeERC721Factory: renounceRole is disabled, use removeAdmin to remove yourself as an admin");
    }

    /// @notice Override revokeRole to disable it.
    function revokeRole(bytes32 role, address) public virtual override onlyRole(getRoleAdmin(role)) {
        revert("SkyBridgeERC721Factory: revokeRole is disabled, use removeAdmin to remove yourself as an admin");
    }
}
