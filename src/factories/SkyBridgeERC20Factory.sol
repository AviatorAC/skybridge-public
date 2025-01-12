// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { SkyBridgeERC20 } from "./SkyBridgeERC20.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title SkyBridgeERC20Factory
 * @notice Factory contract for creating and deploying SkyBridgeERC20 tokens with an admin role.
 */
contract SkyBridgeERC20Factory is AccessControlUpgradeable {
    string public constant version = "1.0.0";

    /// @notice Number of admins on the contract.
    uint256 private _numAdmins;

    /// @notice The Avi Bridge
    address public BRIDGE;

    uint256 public flatFee;

    address public flatFeeRecipient;

    // Mapping of each token to its authorized bridges
    mapping(address => bool) public tokenBridgeAuthorization;

    event SkyBridgeERC20Created(
        address indexed remoteToken,
        address indexed localToken,
        string name,
        string symbol,
        uint8 decimals,
        address deployer
    );

    event BridgeAuthorizationUpdated(
        address indexed bridge,
        bool authorized,
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(bool isTestMode) {
        // isTestMode is used to disable the disabling of the initializers when running tests
        if (!isTestMode) {
            _disableInitializers();
        }
    }

    /**
     * @notice Constructor sets the initial bridge, admin, and fee recipient.
     * @param _bridge Address of the bridge.
     * @param _flatFeeRecipient Address to receive the flat fee.
     */
    function initialize(address _bridge, address _flatFeeRecipient) public initializer {
        __AccessControl_init();

        require(_bridge != address(0), "SkyBridgeERC20Factory: Bridge cannot be zero address");
        require(_flatFeeRecipient != address(0), "SkyBridgeERC20Factory: Fee recipient cannot be zero address");

        BRIDGE = _bridge;

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

    /// @notice Updates the flat fee recipient for all deposits.
    /// @param _recipient New flat fee recipient address
    function setFlatFeeRecipient(address _recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_recipient != address(0), "SkyBridgeERC20Factory: _recipient address cannot be zero");

        address previousFlatFeeRecipient = flatFeeRecipient;

        flatFeeRecipient = _recipient;

        emit FlatFeeRecipientChanged(previousFlatFeeRecipient, flatFeeRecipient, msg.sender);
    }

    /// @notice Override renounceRole to disable it.
    function renounceRole(bytes32, address) public pure override {
        revert("SkyBridgeERC20Factory: renounceRole is disabled, use removeAdmin to remove yourself as an admin");
    }

    /// @notice Override revokeRole to disable it.
    function revokeRole(bytes32 role, address) public virtual override onlyRole(getRoleAdmin(role)) {
        revert("SkyBridgeERC20Factory: revokeRole is disabled, use removeAdmin to remove yourself as an admin");
    }

    /**
     * @notice Deploys a new SkyBridgeERC20 token.
     * @param _remoteToken Address of the corresponding remote token.
     * @param _name        ERC20 name.
     * @param _symbol      ERC20 symbol.
     * @param _decimals    ERC20 decimals.
     */
    function createSkyBridgeERC20(
        address _remoteToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) external payable returns (address) {
        require(_remoteToken != address(0), "SkyBridgeERC20Factory: Remote token cannot be zero address");

        require(msg.value == flatFee, "SkyBridgeERC20Factory: Incorrect flat fee");
        (bool feeSent, ) = payable(flatFeeRecipient).call{value: flatFee}("");
        require(feeSent, "SkyBridgeERC20Factory: Fee transfer failed");

        // Deploy new token
        bytes32 salt = keccak256(abi.encode(_remoteToken, _name, _symbol, _decimals));

        // Try to create a new token with the parameters given (only the factory can call initialize, and it can only be called once)
        SkyBridgeERC20 newSkybridgeERC20 = new SkyBridgeERC20{ salt: salt }(BRIDGE, address(this));
        newSkybridgeERC20.initialize(_remoteToken, _name, _symbol, _decimals);

        emit SkyBridgeERC20Created(_remoteToken, address(newSkybridgeERC20), _name, _symbol, _decimals, msg.sender);

        return address(newSkybridgeERC20);
    }

    /**
     * @notice Adds or removes a bridge authorization.
     * Can only be called by the admin.
     * @param _bridge The bridge address to be added or removed.
     * @param _authorized Boolean to add (true) or remove (false) the authorization.
     */
    function setBridgeAuthorization(address _bridge, bool _authorized) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_bridge != address(0), "SkyBridgeERC20Factory: Bridge address cannot be zero");

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
}
