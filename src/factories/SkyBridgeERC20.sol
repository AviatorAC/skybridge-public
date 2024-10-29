// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ILegacyMintableERC20, IOptimismMintableERC20 } from "@eth-optimism/contracts-bedrock/src/universal/IOptimismMintableERC20.sol";
import { SkyBridgeERC20Factory } from "./SkyBridgeERC20Factory.sol";

/**
 * @title SkyBridgeERC20
 * @notice SkyBridgeERC20 is adapted from OptimismMintableERC20
 */
contract SkyBridgeERC20 is ERC20Upgradeable, IOptimismMintableERC20, ILegacyMintableERC20 {
    string public constant version = "1.0.0";

    /// @notice Address of the corresponding version of this token on the remote chain.
    address public REMOTE_TOKEN;

    /// @notice Admin factory address
    SkyBridgeERC20Factory public immutable FACTORY;

    /// @notice Decimals of the token
    uint8 private DECIMALS;

    /// @notice Address of the StandardBridge on this network.
    address public immutable BRIDGE;

    /// @notice Emitted whenever tokens are minted for an account.
    event Mint(address indexed account, uint256 amount);

    /// @notice Emitted whenever tokens are burned from an account.
    event Burn(address indexed account, uint256 amount);

    constructor(
        address _bridge,
        address _factory
    ) {
        BRIDGE = _bridge;
        FACTORY = SkyBridgeERC20Factory(_factory);
    }

    modifier onlyFactory() {
        require(msg.sender == address(FACTORY), "SkyBridgeERC20: Only the factory can call this function");
        _;
    }

    function initialize(address _remoteToken, string memory _name, string memory _symbol, uint8 _decimals) public onlyFactory initializer {
        __ERC20_init(_name, _symbol);

        REMOTE_TOKEN = _remoteToken;
        DECIMALS = _decimals;
    }

    /**
     * @notice Allows the authorized bridges (checked via the factory) to mint tokens.
     *
     * @param _to     Address to mint tokens to.
     * @param _amount Amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) override(ILegacyMintableERC20, IOptimismMintableERC20) external onlyAuthorizedBridge {
        _mint(_to, _amount);
        emit Mint(_to, _amount);
    }

    /**
     * @notice Allows the authorized bridges (checked via the factory) to burn tokens.
     *
     * @param _from   Address to burn tokens from.
     * @param _amount Amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) override(ILegacyMintableERC20, IOptimismMintableERC20) external onlyAuthorizedBridge {
        _burn(_from, _amount);
        emit Burn(_from, _amount);
    }

    /**
     * @notice Modifier to check if the caller is an authorized bridge via the factory.
     */
    modifier onlyAuthorizedBridge() {
        require(FACTORY.isAuthorizedBridge(msg.sender), "SkyBridge: only authorized bridges can mint/burn");
        _;
    }

    /**
     * @notice ERC165 interface check function.
     *
     * @param _interfaceId Interface ID to check.
     *
     * @return Whether or not the interface is supported by this contract.
     */
    function supportsInterface(bytes4 _interfaceId) external pure override returns (bool) {
        bytes4 iface1 = type(IERC165).interfaceId;
        bytes4 iface2 = type(ILegacyMintableERC20).interfaceId;
        bytes4 iface3 = type(IOptimismMintableERC20).interfaceId;
        return _interfaceId == iface1 || _interfaceId == iface2 || _interfaceId == iface3;
    }

    /// @dev Returns the number of decimals used for the token.
    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @custom:legacy
     * @notice Legacy getter for the remote token. Use REMOTE_TOKEN going forward.
     */
    function l1Token() public view returns (address) {
        return REMOTE_TOKEN;
    }

    /**
     * @custom:legacy
     * @notice Legacy getter for REMOTE_TOKEN.
     */
    function remoteToken() public view returns (address) {
        return REMOTE_TOKEN;
    }

    /**
     * @custom:legacy
     * @notice Legacy getter for deployerBridge.
     */
    function bridge() public view returns (address) {
        return BRIDGE;
    }
}

