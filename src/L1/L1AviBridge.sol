// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AviPredeploys } from "src/libraries/AviPredeploys.sol";
import { AviBridge } from "src/universal/AviBridge.sol";
import { ISemver } from "@eth-optimism/contracts-bedrock/src/universal/ISemver.sol";
import { CrossDomainMessenger } from "@eth-optimism/contracts-bedrock/src/universal/CrossDomainMessenger.sol";
import { Constants } from "@eth-optimism/contracts-bedrock/src/libraries/Constants.sol";
import { LiquidityPool } from "src/L1/LiquidityPool.sol";

/// @custom:proxied
/// @title L1AviBridge
/// @notice The L1AviBridge is responsible for transfering ETH and ERC20 tokens between L1 and
///         L2. In the case that an ERC20 token is native to L1, it will be escrowed within this
///         contract. If the ERC20 token is native to L2, it will be burnt. Before Bedrock, ETH was
///         stored within this contract. After Bedrock, ETH is instead stored inside the
///         OptimismPortal contract.
///         NOTE: this contract is not intended to support all variations of ERC20 tokens. Examples
///         of some token types that may not be properly supported by this contract include, but are
///         not limited to: tokens with transfer fees, rebasing tokens, and tokens with blocklists.
contract L1AviBridge is AviBridge, ISemver {
    using SafeERC20 for IERC20;

    /// @custom:legacy
    /// @notice Emitted whenever a deposit of ETH from L1 into L2 is initiated.
    /// @param from      Address of the depositor.
    /// @param to        Address of the recipient on L2.
    /// @param amount    Amount of ETH deposited.
    /// @param extraData Extra data attached to the deposit.
    event ETHDepositInitiated(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @custom:legacy
    /// @notice Emitted whenever a withdrawal of ETH from L2 to L1 is finalized.
    /// @param from      Address of the withdrawer.
    /// @param to        Address of the recipient on L1.
    /// @param amount    Amount of ETH withdrawn.
    /// @param extraData Extra data attached to the withdrawal.
    event ETHWithdrawalFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @custom:legacy
    /// @notice Emitted whenever an ERC20 deposit is initiated.
    /// @param l1Token   Address of the token on L1.
    /// @param l2Token   Address of the corresponding token on L2.
    /// @param from      Address of the depositor.
    /// @param to        Address of the recipient on L2.
    /// @param amount    Amount of the ERC20 deposited.
    /// @param extraData Extra data attached to the deposit.
    event ERC20DepositInitiated(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @custom:legacy
    /// @notice Emitted whenever an ERC20 withdrawal is finalized.
    /// @param l1Token   Address of the token on L1.
    /// @param l2Token   Address of the corresponding token on L2.
    /// @param from      Address of the withdrawer.
    /// @param to        Address of the recipient on L1.
    /// @param amount    Amount of the ERC20 withdrawn.
    /// @param extraData Extra data attached to the withdrawal.
    event ERC20WithdrawalFinalized(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @notice Semantic version.
    /// @custom:semver 2.0.0
    string public constant version = "2.0.0";

    /// @notice The flat bridging fee for all deposits. Measured in ETH.
    uint256 public flatFee = 0.001 ether;

    /// @notice The numerator component of the percentage based briding fee for all deposits.
    uint256 public bridgingFee = 3;

    /// @notice if the bridge is paused
    bool _isPaused = false;

    /// @notice the liquidity pool
    LiquidityPool public LIQUIDITY_POOL;

    /// @notice The address of the Aviator token on the L1 chain
    address public L1AviToken;

    /// @notice The address of the receiver of the flat fee
    address public flatFeeReceipient;

    /// @notice Mapping of the available ETH for each user
    mapping(address => uint256) private fastBridgeBalances;

    /// @notice Mapping of the available ERC20 for each user
    mapping(address => mapping(address => uint256)) private fastBridgeERC20Balances;

    /// @notice Constructs the L1AviBridge contract.
    constructor(address payable _liquidityPool, address _token) AviBridge(payable(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER), payable(AviPredeploys.L2_STANDARD_BRIDGE)) {
        require(_liquidityPool != address(0), "AviBridge: LiquidityPool address cannot be zero");
        require(_token != address(0), "AviBridge: Avi L1 Token address cannot be zero");

        LIQUIDITY_POOL = LiquidityPool(_liquidityPool);
        flatFeeReceipient = _liquidityPool;
        L1AviToken = _token;
        _isPaused = false;
    }

    /// @notice Updates the flat fee for all deposits.
    /// @param _fee New flat fee.
    function setFlatFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_fee < 0.005 ether, "AviBridge: _fee must be less than 0.005 ether");
        flatFee = _fee;
    }

    /// @notice Updates the flat fee recipient for all deposits.
    /// @param _recipient New flat fee recipient address
    function setFlatFeeRecipient(address _recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_recipient != address(0), "AviBridge: _recipient address cannot be zero");
        flatFeeReceipient = _recipient;
    }

    /// @notice Updates the numerator component of the percentage based briding fee for all deposits.
    /// @param _fee New numerator component of the percentage based briding fee.
    function setBridgingFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_fee <= 100, "AviBridge: _fee must be less than or equal to 100");
        bridgingFee = _fee;
    }

    /// @notice Updates the paused status of the bridge
    /// @param _paused New paused status
    function setPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _isPaused = _paused;
    }

    /// @notice Updates the the address of the other bridge contract.
    /// @param _otherBridge Address of the other bridge contract.
    function setOtherBridge(address _otherBridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_otherBridge != address(0), "AviBridge: _otherBridge address cannot be zero");
        OTHER_BRIDGE = AviBridge(payable(_otherBridge));
    }

    /// @notice Sets the address for the Avi L1 token so that it may avoid fees
    /// @param _token Address of the token contract
    function setAviTokenAddress(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(0), "AviBridge: _token address cannot be zero");
        L1AviToken = _token;
    }

    /// @inheritdoc AviBridge
    function paused() public view override returns (bool) {
        return _isPaused;
    }

    /// @notice Allows EOAs to bridge ETH by sending directly to the bridge.
    receive() external payable override onlyEOA {
        _initiateETHDeposit(msg.sender, msg.sender, RECEIVE_DEFAULT_GAS_LIMIT, bytes(""));
    }

    /// @custom:legacy
    /// @notice Deposits some amount of ETH into the sender's account on L2.
    /// @param _minGasLimit Minimum gas limit for the deposit message on L2.
    /// @param _extraData   Optional data to forward to L2.
    ///                     Data supplied here will not be used to execute any code on L2 and is
    ///                     only emitted as extra data for the convenience of off-chain tooling.
    function bridgeETH(uint32 _minGasLimit, bytes calldata _extraData) external payable onlyEOA {
        _initiateETHDeposit(msg.sender, msg.sender, _minGasLimit, _extraData);
    }

    /// @custom:legacy
    /// @notice Deposits some amount of ETH into a target account on L2.
    ///         Note that if ETH is sent to a contract on L2 and the call fails, then that ETH will
    ///         be locked in the L2AviBridge. ETH may be recoverable if the call can be
    ///         successfully replayed by increasing the amount of gas supplied to the call. If the
    ///         call will fail for any amount of gas, then the ETH will be locked permanently.
    /// @param _to          Address of the recipient on L2.
    /// @param _minGasLimit Minimum gas limit for the deposit message on L2.
    /// @param _extraData   Optional data to forward to L2.
    ///                     Data supplied here will not be used to execute any code on L2 and is
    ///                     only emitted as extra data for the convenience of off-chain tooling.
    function bridgeETHTo(address _to, uint32 _minGasLimit, bytes calldata _extraData) external payable {
        _initiateETHDeposit(msg.sender, _to, _minGasLimit, _extraData);
    }

    /// @custom:legacy
    /// @notice Deposits some amount of ERC20 tokens into the sender's account on L2.
    /// @param _l1Token     Address of the L1 token being deposited.
    /// @param _l2Token     Address of the corresponding token on L2.
    /// @param _amount      Amount of the ERC20 to deposit.
    /// @param _minGasLimit Minimum gas limit for the deposit message on L2.
    /// @param _extraData   Optional data to forward to L2.
    ///                     Data supplied here will not be used to execute any code on L2 and is
    ///                     only emitted as extra data for the convenience of off-chain tooling.
    function bridgeERC20(
        address _l1Token,
        address _l2Token,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        virtual
        payable
        onlyEOA
    {
        _initiateERC20Deposit(_l1Token, _l2Token, msg.sender, msg.sender, _amount, _minGasLimit, _extraData);
    }

    /// @custom:legacy
    /// @notice Deposits some amount of ERC20 tokens into a target account on L2.
    /// @param _l1Token     Address of the L1 token being deposited.
    /// @param _l2Token     Address of the corresponding token on L2.
    /// @param _to          Address of the recipient on L2.
    /// @param _amount      Amount of the ERC20 to deposit.
    /// @param _minGasLimit Minimum gas limit for the deposit message on L2.
    /// @param _extraData   Optional data to forward to L2.
    ///                     Data supplied here will not be used to execute any code on L2 and is
    ///                     only emitted as extra data for the convenience of off-chain tooling.
    function bridgeERC20To(
        address _l1Token,
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        virtual
        payable
    {
        _initiateERC20Deposit(_l1Token, _l2Token, msg.sender, _to, _amount, _minGasLimit, _extraData);
    }

    /// @custom:legacy
    /// @notice Finalizes a withdrawal of ETH from L2.
    /// @param _from      Address of the withdrawer on L2.
    /// @param _to        Address of the recipient on L1.
    /// @param _amount    Amount of ETH to withdraw.
    /// @param _extraData Optional data forwarded from L2.
    function finalizeETHWithdrawal(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
        payable
    {
        finalizeBridgeETH(_from, _to, _amount, _extraData);
    }

    /// @notice Finalizes a fast ETH bridge on this chain. Can only be triggered by the other
    ///         AviBridge contract on the remote chain.
    /// @param _from      Address of the sender.
    /// @param _to        Address of the receiver.
    /// @param _amount    Amount of ETH being bridged.
    /// @param _extraData Extra data to be sent with the transaction. Note that the recipient will
    ///                   not be triggered with this data, but it will be emitted and can be used
    ///                   to identify the transaction.
    function finalizeFastBridgeETH(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(paused() == false, "AviBridge: paused");
        require(_to != address(this), "AviBridge: cannot send to self");
        require(_to != address(MESSENGER), "AviBridge: cannot send to messenger");

        // Mark the ETH as available to the recipient
        makeAvailable(_to, _amount);
        // Emit the correct events. By default this will be _amount, but child
        // contracts may override this function in order to emit legacy events as well.
        _emitETHBridgeFinalized(_from, _to, _amount, _extraData);
    }

    /// @custom:legacy
    /// @notice Finalizes a withdrawal of ERC20 tokens from L2.
    /// @param _l1Token   Address of the token on L1.
    /// @param _l2Token   Address of the corresponding token on L2.
    /// @param _from      Address of the withdrawer on L2.
    /// @param _to        Address of the recipient on L1.
    /// @param _amount    Amount of the ERC20 to withdraw.
    /// @param _extraData Optional data forwarded from L2.
    function finalizeERC20Withdrawal(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
    {
        finalizeBridgeERC20(_l1Token, _l2Token, _from, _to, _amount, _extraData);
    }

    /// @notice Finalizes an ERC20 fast bridge on this chain. Can only be triggered by the other
    ///         AviBridge contract on the remote chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the ERC20 being bridged.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function finalizeFastBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(paused() == false, "AviBridge: paused");
        deposits[_localToken][_remoteToken] = deposits[_localToken][_remoteToken] - _amount;
        // Mark the ERC20 as available to the recipient
        makeERC20Available(_to, _localToken, _amount);

        // Emit the correct events. By default this will be ERC20BridgeFinalized, but child
        // contracts may override this function in order to emit legacy events as well.
        _emitERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @notice Records that a user has ETH funds available to withdraw.
    /// This doesn't actually transfer any ETH, it just records that the user has ETH available to withdraw.
    /// @param _recipient Address of the user.
    /// @param _amount Amount of eth to deposit.
    function makeAvailable(address _recipient, uint256 _amount) internal {
        require(_amount > 0, "AviBridge: Must deposit more than 0");
        fastBridgeBalances[_recipient] += _amount;
    }

    /// @notice Records that a user has ERC20 funds available to withdraw.
    /// This doesn't actually transfer any ERC20, it just records that the user has ERC20 available to withdraw.
    /// @param _recipient Address of the user.
    /// @param _token Address of the token contract that you want to deposit.
    /// @param _amount Amount of the token to deposit.
    function makeERC20Available(address _recipient, address _token, uint256 _amount) internal {
        require(_amount > 0, "AviBridge: Must deposit more than 0");
        fastBridgeERC20Balances[_recipient][_token] += _amount;
    }

    /// @notice Withdraw ETH from the bridge.
    /// @param _amount Amount of eth to withdraw.
    function withdraw(uint256 _amount) external {
        require(_amount > 0, "AviBridge: Must withdraw more than 0");
        require(fastBridgeBalances[msg.sender] >= _amount, "AviBridge: Insufficient balance");
        LIQUIDITY_POOL.sendETH(msg.sender, _amount);
        fastBridgeBalances[msg.sender] -= _amount;
    }

    /// @notice Withdraw ERC20 from the bridge.
    /// @param _token Address of the token contract that you want to withdraw.
    /// @param _amount Amount of the token to withdraw.
    function withdrawERC20(address _token, uint256 _amount) external {
        require(_amount > 0, "AviBridge: Must withdraw more than 0");
        require(_token != address(0), "AviBridge: Token address cannot be zero");
        require(fastBridgeERC20Balances[msg.sender][_token] >= _amount, "AviBridge: Insufficient balance");
        LIQUIDITY_POOL.sendERC20(msg.sender, _token, _amount);
        fastBridgeERC20Balances[msg.sender][_token] -= _amount;
    }

    /// @notice Returns the available fast bridging ETH for the caller.
    function availableETH() external view returns (uint256) {
        return fastBridgeBalances[msg.sender];
    }

    /// @notice Returns the available fast bridging ERC20 for the caller.
    /// @param _token Address of the token contract that you want to check the balance of.
    function availableERC20(address _token) external view returns (uint256) {
        return fastBridgeERC20Balances[msg.sender][_token];
    }

    /// @custom:legacy
    /// @notice Retrieves the access of the corresponding L2 bridge contract.
    /// @return Address of the corresponding L2 bridge contract.
    function l2TokenBridge() external view returns (address) {
        return address(OTHER_BRIDGE);
    }

    /// @notice Internal function for initiating an ETH deposit.
    /// @param _from        Address of the sender on L1.
    /// @param _to          Address of the recipient on L2.
    /// @param _minGasLimit Minimum gas limit for the deposit message on L2.
    /// @param _extraData   Optional data to forward to L2.
    function _initiateETHDeposit(address _from, address _to, uint32 _minGasLimit, bytes memory _extraData) internal {
        uint256 totalFee = msg.value * bridgingFee / 1000 + flatFee;
        require(msg.value >= totalFee, "AviBridge: insufficient ETH value");

        uint256 bridgeFee = msg.value * bridgingFee / 1000;
        uint256 _amount = msg.value - totalFee;

        (bool sentToFlatFee, ) = payable(flatFeeReceipient).call{value: flatFee}("");
        require(sentToFlatFee, "AviBridge: transfer of flat fee to flat fee pool failed");

        (bool sent, ) = payable(LIQUIDITY_POOL).call{value: bridgeFee}("");
        require(sent, "AviBridge: transfer of bridging fee to liquidity pool failed");

        _initiateBridgeETH(_from, _to, _amount, _minGasLimit, _extraData);
    }

    /// @notice Internal function for initiating an ERC20 deposit.
    /// @param _l1Token     Address of the L1 token being deposited.
    /// @param _l2Token     Address of the corresponding token on L2.
    /// @param _from        Address of the sender on L1.
    /// @param _to          Address of the recipient on L2.
    /// @param _amount      Amount of the ERC20 to deposit.
    /// @param _minGasLimit Minimum gas limit for the deposit message on L2.
    /// @param _extraData   Optional data to forward to L2.
    function _initiateERC20Deposit(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        internal
    {
        require(msg.value == flatFee, "AviBridge: bridging ERC20 must include sufficient ETH value");

        (bool sent, ) = payable(flatFeeReceipient).call{value: msg.value}("");
        require(sent, "AviBridge: transfer of flat fee to flat fee pool failed");

        // For ERC20 tokens that aren't the L1AviToken, we also want to take the bridging fee
        if (_l1Token != L1AviToken) {
            uint256 fee = _amount * bridgingFee / 1000;
            _amount = _amount - fee;

            IERC20(_l1Token).safeTransferFrom(_from, address(LIQUIDITY_POOL), fee);
        }

        _initiateBridgeERC20(_l1Token, _l2Token, _from, _to, _amount, _minGasLimit, _extraData);
    }

    /// @inheritdoc AviBridge
    /// @notice Emits the legacy ETHDepositInitiated event followed by the ETHBridgeInitiated event.
    ///         This is necessary for backwards compatibility with the legacy bridge.
    function _emitETHBridgeInitiated(
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        override
    {
        emit ETHDepositInitiated(_from, _to, _amount, _extraData);
        super._emitETHBridgeInitiated(_from, _to, _amount, _extraData);
    }

    /// @inheritdoc AviBridge
    /// @notice Emits the legacy ERC20DepositInitiated event followed by the ERC20BridgeInitiated
    ///         event. This is necessary for backwards compatibility with the legacy bridge.
    function _emitETHBridgeFinalized(
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        override
    {
        emit ETHWithdrawalFinalized(_from, _to, _amount, _extraData);
        super._emitETHBridgeFinalized(_from, _to, _amount, _extraData);
    }

    /// @inheritdoc AviBridge
    /// @notice Emits the legacy ERC20WithdrawalFinalized event followed by the ERC20BridgeFinalized
    ///         event. This is necessary for backwards compatibility with the legacy bridge.
    function _emitERC20BridgeInitiated(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        override
    {
        emit ERC20DepositInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);
        super._emitERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @inheritdoc AviBridge
    /// @notice Emits the legacy ERC20WithdrawalFinalized event followed by the ERC20BridgeFinalized
    ///         event. This is necessary for backwards compatibility with the legacy bridge.
    function _emitERC20BridgeFinalized(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        override
    {
        emit ERC20WithdrawalFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
        super._emitERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }
}
