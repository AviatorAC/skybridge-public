// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { SkyBridgeERC20 } from "./SkyBridgeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BasedERC20Factory
 * @notice Factory contract for creating and deploying BasedMigrateERC20 tokens.
 */
contract SkyBridgeERC20Factory is Ownable {
    /**
     * @notice Returns the version of the BasedERC20Factory contract
     */
    string public constant version = "1.0.0";

    /**
     * @notice Address of the SkybridgeBridge on this chain.
     */
    address public immutable BRIDGE;

    /// @notice The flat bridging fee for all deposits. Measured in ETH.
    uint256 public flatFee = 0.005 ether;

    /// @notice The address of the receiver of the flat fee.
    address public flatFeeRecipient;

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

    /**
     * @dev Emitted when a new SkybridgeERC20 token is created.
     * @param remoteToken Address of the remote token.
     * @param localToken Address of the newly created local token.
     * @param deployer Address of the deployer.
     */
    event SkybridgeERC20Created(address indexed remoteToken, address indexed localToken, address deployer);

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

    /**
     * @notice constructor
     * @param _bridge Address of the StandardBridge.
     * @param _flatFeeRecipient Address of the flat fee recipient.
     */
    constructor(address _bridge, address _flatFeeRecipient) {
        if (_bridge == address(0)) revert BridgeAddressCannotBeZero();
        if (_flatFeeRecipient == address(0)) revert FlatFeeRecipientCannotBeZero();

        BRIDGE = _bridge;
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

    /**
     * @notice Deploys a new SkybridgeErc20 token clone with specified parameters.
     * @param _remoteToken Address of the remote token to be based on.
     * @param _name Name for the new token.
     * @param _symbol Symbol for the new token.
     * @return Address of the newly deployed SkybridgeErc20 token.
     * @param _decimals ERC20 decimals
     */
    function createSkyBridgeERC20(
        address _remoteToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) external payable returns (address) {
        if (_remoteToken == address(0)) {
            revert RemoteTokenCannotBeZeroAddress();
        }

        require(msg.value == flatFee, "SkyBridge: incorrect flat fee sent");

        (bool sentToFlatFee, ) = payable(flatFeeRecipient).call{value: flatFee}("");
        require(sentToFlatFee, "SkyBridge: transfer of flat fee failed");

        // deploy clone
        bytes32 salt = keccak256(abi.encode(_remoteToken, _name, _symbol, _decimals));
        address newSkybridgeERC20 = address(new SkyBridgeERC20{ salt: salt }(BRIDGE, _remoteToken, _name, _symbol, _decimals));

        emit SkybridgeERC20Created(_remoteToken, newSkybridgeERC20, msg.sender);

        return newSkybridgeERC20;
    }
}
