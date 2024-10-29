// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LiquidityPool is AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant BRIDGE_ROLE = keccak256("aviator.bridge_role");

    uint256 internal _numAdmins;

    string public constant version = "1.0.1";

    /**
     * @dev This gap is used to allow further fields on base contracts without causing possible storage clashes.
     */
    uint256[49] private __gap;

    /// @notice Emitted when a bridge is added.
    /// @param bridgeAddress Address of the bridge.
    /// @param addedBy       Address of the caller.
    event BridgeAdded(
        address bridgeAddress,
        address addedBy
    );

    /// @notice Emitted when a bridge is removed.
    /// @param bridgeAddress Address of the bridge.
    /// @param removedBy     Address of the caller.
    event BridgeRemoved(
        address bridgeAddress,
        address removedBy
    );

    /// @notice Emitted when a admin is added.
    /// @param adminAddress  Address of the admin.
    /// @param addedBy       Address of the caller.
    event AdminAdded(
        address adminAddress,
        address addedBy
    );

    /// @notice Emitted when a admin is removed.
    /// @param adminAddress  Address of the admin.
    /// @param removedBy     Address of the caller.
    event AdminRemoved(
        address adminAddress,
        address removedBy
    );

    /// @notice Emitted when ETH is send.
    /// @param amount           uint256 of the amount.
    /// @param to               Address of the recipient.
    /// @param executedBy       Address of the caller.
    event ETHSend(
        uint256 amount,
        address to,
        address executedBy
    );

    /// @notice Emitted when ERC20 is send.
    /// @param amount           uint256 of the amount.
    /// @param to               Address of the recipient.
    /// @param executedBy       Address of the caller.
    event ERC20Send(
        uint256 amount,
        address to,
        address executedBy
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(bool isTestMode) {
        // isTestMode is used to disable the disabling of the initializers when running tests
        if (!isTestMode) {
            _disableInitializers();
        }
    }

    function initialize() public initializer {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); // make the deployer admin
        _numAdmins = 1;
    }

    /// @notice Add a new admin address to the list of admins.
    /// @param _admin New admin address.
    function addAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!hasRole(DEFAULT_ADMIN_ROLE, _admin), "Admin already added.");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _numAdmins++;

        emit AdminAdded(_admin, msg.sender);
    }

    /// @notice Remove an admin from the list of admins.
    /// @param _admin Address to remove.
    function removeAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(DEFAULT_ADMIN_ROLE, _admin), "Address is not a recognized admin.");
        require (_numAdmins > 1, "Cannot remove the only admin.");

        _revokeRole(DEFAULT_ADMIN_ROLE, _admin);
        _numAdmins--;

        emit AdminRemoved(_admin, msg.sender);
    }

    /// @notice Add a new bridge address to the list of bridges.
    /// @param _bridge New bridge address.
    function addBridge(address _bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!hasRole(BRIDGE_ROLE, _bridge), "Bridge already added.");

        _grantRole(BRIDGE_ROLE, _bridge);

        emit BridgeAdded(_bridge, msg.sender);
    }

    /// @notice Remove a bridge from the list of bridges.
    /// @param _bridge Address to remove.
    function removeBridge(address _bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(BRIDGE_ROLE, _bridge), "Address is not a recognized bridge.");

        _revokeRole(BRIDGE_ROLE, _bridge);

        emit BridgeRemoved(_bridge, msg.sender);
    }

    /// @notice Send ETH from this contract to another address.
    /// @param _to Address to send eth to.
    /// @param _amount Amount of eth to send.
    function sendETH(address _to, uint256 _amount) external onlyRole(BRIDGE_ROLE) {
        require(_to != address(0), "LiquidityPool: _to address cannot be zero");
        (bool sent, ) = _to.call{value: _amount}("");
        require(sent, "failed to send ether");
        emit ETHSend(_amount, _to, msg.sender);
    }

    /// @notice Send ERC20 from this contract to another address.
    /// @param _to Address to send to.
    /// @param _token Address of the token contract that you want to send.
    /// @param _amount Amount of the token to send.
    function sendERC20(address _to, address _token, uint256 _amount) external onlyRole(BRIDGE_ROLE) {
        IERC20(_token).safeTransfer(_to, _amount);
        emit ERC20Send(_amount, _to, msg.sender);
    }

    /// @notice Widthdraw an ETH amount from this contract.
    /// @param _amount Amount of eth to withdraw.
    function withdrawETH(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool sent, ) = msg.sender.call{value: _amount}("");
        require(sent, "failed to send ether");
    }

    /// @notice Widthdraw an ERC20 amount from this contract.
    /// @param _token Address of the token contract that you want to withdraw.
    /// @param _amount Amount of the token to withdraw.
    function withdrawERC20(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /// @notice Allows this contract to receive eth.
    receive() external payable {}

    /// @notice Allows this contract to receive ERC20 tokens.
    /// @param _token Address of the token contract to receive.
    /// @param _amount Amount of the token to receive.
    function receiveERC20(address _token, uint256 _amount) external {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice Returns the balance of the given token stored in this contract.
    /// @param _token Token to check the balance of.
    function getERC20Balance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /// @notice Returns the balance of eth stored in this contract.
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Override renounceRole to disable it.
    function renounceRole(bytes32, address) public pure override {
        revert("LiquidityPool: renounceRole is disabled, use removeAdmin to remove yourself as an admin");
    }

    /// @notice Override revokeRole to disable it.
    function revokeRole(bytes32 role, address) public virtual override onlyRole(getRoleAdmin(role)) {
        revert("LiquidityPool: revokeRole is disabled, use removeAdmin to remove yourself as an admin");
    }
}
