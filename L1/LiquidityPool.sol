// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LiquidityPool is AccessControl {
    using SafeERC20 for IERC20;

    uint internal _numAdmins = 0;

    event AdminAdded(address adminAddress);
    event AdminRemoved(address adminAddress);
    /// @notice Constructs the LiquidityPool contract.
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); // make the deployer admin
        _numAdmins++;
    }

    /// @notice Add a new admin address to the list of admins.
    /// @param _admin New admin address.
    function addAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!hasRole(DEFAULT_ADMIN_ROLE, _admin), "Admin already added.");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _numAdmins++;

        emit AdminAdded(_admin);
    }

    /// @notice Remove an admin from the list of admins.
    /// @param _admin Address to remove.
    function removeAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(DEFAULT_ADMIN_ROLE, _admin), "Address is not a recognized admin.");
        require (_numAdmins > 1, "Cannot remove the only admin.");

        _revokeRole(DEFAULT_ADMIN_ROLE, _admin);
        _numAdmins--;

        emit AdminRemoved(_admin);
    }

    /// @notice Send ethereum from this contract to another address.
    /// @param _to Address to send eth to.
    /// @param _amount Amount of eth to send.
    function sendETH(address _to, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_to != address(0), "LiquidityPool: _to address cannot be zero");
        (bool sent, ) = _to.call{value: _amount}("");
        require(sent, "failed to send ether");
    }

    /// @notice Send ERC20 from this contract to another address.
    /// @param _to Address to send to.
    /// @param _token Address of the token contract that you want to send.
    /// @param _amount Amount of the token to send.
    function sendERC20(address _to, address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /// @notice Allows this contract to receive eth.
    receive() external payable {}

    /// @notice Allows this contract to receive ERC20 tokens.
    /// @param _from Address to transfer the ERC20 token from.
    /// @param _token Address of the token contract to receive.
    /// @param _amount Amount of the token to receive.
    function receiveERC20(address _from, address _token, uint256 _amount) external {
        IERC20(_token).safeTransferFrom(_from, address(this), _amount);
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
}
