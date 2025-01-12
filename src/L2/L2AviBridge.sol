// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Predeploys } from "@eth-optimism/contracts-bedrock/src/libraries/Predeploys.sol";
import { AviBridge } from "src/universal/AviBridge.sol";
import { OptimismMintableERC20 } from "@eth-optimism/contracts-bedrock/src/universal/OptimismMintableERC20.sol";
import { CrossDomainMessenger } from "@eth-optimism/contracts-bedrock/src/universal/CrossDomainMessenger.sol";

/// @custom:proxied
/// @title L2AviBridge
/// @notice The L2AviBridge is responsible for transfering ETH and ERC20 tokens between L1 and
///         L2. In the case that an ERC20 token is native to L2, it will be escrowed within this
///         contract. If the ERC20 token is native to L1, it will be burnt.
///         NOTE: this contract is not intended to support all variations of ERC20 tokens. Examples
///         of some token types that may not be properly supported by this contract include, but are
///         not limited to: tokens with transfer fees, rebasing tokens, and tokens with blocklists.
contract L2AviBridge is AviBridge {
    /// @custom:legacy
    /// @notice Emitted whenever a withdrawal from L2 to L1 is initiated.
    /// @param l1Token   Address of the token on L1.
    /// @param l2Token   Address of the corresponding token on L2.
    /// @param from      Address of the withdrawer.
    /// @param to        Address of the recipient on L1.
    /// @param amount    Amount of the ERC20 withdrawn.
    /// @param extraData Extra data attached to the withdrawal.
    event WithdrawalInitiated(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @custom:legacy
    /// @notice Emitted whenever an ERC20 deposit is finalized.
    /// @param l1Token   Address of the token on L1.
    /// @param l2Token   Address of the corresponding token on L2.
    /// @param from      Address of the depositor.
    /// @param to        Address of the recipient on L2.
    /// @param amount    Amount of the ERC20 deposited.
    /// @param extraData Extra data attached to the deposit.
    event DepositFinalized(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @notice Emitted whenever a fast withdrawal from L2 to L1 is initiated.
    /// @param l1Token   Address of the token on L1.
    /// @param l2Token   Address of the corresponding token on L2.
    /// @param from      Address of the withdrawer.
    /// @param to        Address of the recipient on L1.
    /// @param amount    Amount of the ERC20 withdrawn.
    /// @param extraData Extra data attached to the withdrawal.
    event FastWithdrawalInitiated(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @notice Emitted whenever a token is added to the allow list.
    /// @param token             Address of the token .
    /// @param executedBy        Address of the caller.
    event AllowedTokenAdded(
        address token,
        address executedBy
    );

    /// @notice Emitted whenever a token is removed from the allow list.
    /// @param token             Address of the token .
    /// @param executedBy        Address of the caller.
    event AllowedTokenRemoved(
        address token,
        address executedBy
    );

    /// @notice Semantic version.
    string public constant version = "1.2.1";

    /// @notice Mapping that stores deposits for a given pair of local and remote tokens.
    mapping(address => bool) public allowedTokens;

    address public liquidityPool;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(bool isTestMode) {
        // isTestMode is used to disable the disabling of the initializers when running tests
        if (!isTestMode) {
            _disableInitializers();
        }
    }

    /// @notice Constructs the L2AviBridge contract.
    /// @param _otherBridge Address of the L1AviBridge.
    /// @param _liquidityPool Address of the liquidityPool.
    /// @param _l1FeeRecipient Address of the l1FeeRecipient.
    function initialize(
        // Optimism stack
        address payable _l2CrossDomainMessenger,
        // AVI stack
        address payable _otherBridge,
        address payable _liquidityPool,
        address payable _l1FeeRecipient
    ) public initializer {
        require(_l2CrossDomainMessenger != address(0), "AviBridge: _l2CrossDomainMessenger address cannot be zero");

        require(_otherBridge != address(0), "AviBridge: _otherBridge address cannot be zero");
        require(_liquidityPool != address(0), "AviBridge: _liquidityPool address cannot be zero");
        require(_l1FeeRecipient != address(0), "AviBridge: _l1FeeRecipient address cannot be zero");

        __SkyBridge_init(_l2CrossDomainMessenger, _otherBridge);

        liquidityPool = _liquidityPool;
        flatFeeRecipient = _l1FeeRecipient;
    }

    /// @notice Allows EOAs to bridge ETH by sending directly to the bridge.
    receive() external payable override onlyEOA {
        _initiateWithdrawal(
            Predeploys.LEGACY_ERC20_ETH, msg.sender, msg.sender, msg.value, RECEIVE_DEFAULT_GAS_LIMIT, false, bytes("")
        );
    }

    /// @custom:legacy
    /// @notice Initiates a withdrawal from L2 to L1.
    ///         This function only works with OptimismMintableERC20 tokens or ether. Use the
    ///         `bridgeERC20` function to bridge native L2 tokens to L1.
    /// @param _l2Token     Address of the L2 token to withdraw.
    /// @param _amount      Amount of the L2 token to withdraw.
    /// @param _minGasLimit Minimum gas limit to use for the transaction.
    /// @param _extraData   Extra data attached to the withdrawal.
    function withdraw(
        address _l2Token,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        payable
        virtual
        onlyEOA
    {
        _initiateWithdrawal(_l2Token, msg.sender, msg.sender, _amount, _minGasLimit, false, _extraData);
    }

    /// @custom:legacy
    /// @notice Initiates a withdrawal from L2 to L1 to a target account on L1.
    ///         Note that if ETH is sent to a contract on L1 and the call fails, then that ETH will
    ///         be locked in the L1AviBridge. ETH may be recoverable if the call can be
    ///         successfully replayed by increasing the amount of gas supplied to the call. If the
    ///         call will fail for any amount of gas, then the ETH will be locked permanently.
    ///         This function only works with OptimismMintableERC20 tokens or ether. Use the
    ///         `bridgeERC20To` function to bridge native L2 tokens to L1.
    /// @param _l2Token     Address of the L2 token to withdraw.
    /// @param _to          Recipient account on L1.
    /// @param _amount      Amount of the L2 token to withdraw.
    /// @param _minGasLimit Minimum gas limit to use for the transaction.
    /// @param _extraData   Extra data attached to the withdrawal.
    function withdrawTo(
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        payable
        virtual
    {
        _initiateWithdrawal(_l2Token, msg.sender, _to, _amount, _minGasLimit, false, _extraData);
    }

    /// @custom:legacy
    /// @notice Initiates a withdrawal from L2 to L1 to a target account on L1.
    ///         Note that if ETH is sent to a contract on L1 and the call fails, then that ETH will
    ///         be locked in the L1AviBridge. ETH may be recoverable if the call can be
    ///         successfully replayed by increasing the amount of gas supplied to the call. If the
    ///         call will fail for any amount of gas, then the ETH will be locked permanently.
    ///         This function only works with OptimismMintableERC20 tokens or ether. Use the
    ///         `bridgeERC20To` function to bridge native L2 tokens to L1.
    /// @param _l2Token     Address of the L2 token to withdraw.
    /// @param _amount      Amount of the L2 token to withdraw.
    /// @param _minGasLimit Minimum gas limit to use for the transaction.
    /// @param _extraData   Extra data attached to the withdrawal.
    function fastWithdraw(
        address _l2Token,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        payable
        virtual
        onlyEOA
    {
        _initiateWithdrawal(_l2Token, msg.sender, msg.sender, _amount, _minGasLimit, true, _extraData);
    }

    /// @custom:legacy
    /// @notice Initiates a withdrawal from L2 to L1 to a target account on L1.
    ///         Note that if ETH is sent to a contract on L1 and the call fails, then that ETH will
    ///         be locked in the L1AviBridge. ETH may be recoverable if the call can be
    ///         successfully replayed by increasing the amount of gas supplied to the call. If the
    ///         call will fail for any amount of gas, then the ETH will be locked permanently.
    ///         This function only works with OptimismMintableERC20 tokens or ether. Use the
    ///         `bridgeERC20To` function to bridge native L2 tokens to L1.
    /// @param _l2Token     Address of the L2 token to withdraw.
    /// @param _to          Recipient account on L1.
    /// @param _amount      Amount of the L2 token to withdraw.
    /// @param _minGasLimit Minimum gas limit to use for the transaction.
    /// @param _extraData   Extra data attached to the withdrawal.
    function fastWithdrawTo(
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        payable
        virtual
    {
        _initiateWithdrawal(_l2Token, msg.sender, _to, _amount, _minGasLimit, true, _extraData);
    }

    /// @custom:legacy
    /// @notice Finalizes a deposit from L1 to L2. To finalize a deposit of ether, use address(0)
    ///         and the l1Token and the Legacy ERC20 ether predeploy address as the l2Token.
    /// @param _l1Token   Address of the L1 token to deposit.
    /// @param _l2Token   Address of the corresponding L2 token.
    /// @param _from      Address of the depositor.
    /// @param _to        Address of the recipient.
    /// @param _amount    Amount of the tokens being deposited.
    /// @param _extraData Extra data attached to the deposit.
    function finalizeDeposit(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
        payable
        virtual
    {
        require(_to != address(0), "L2AviBridge: cannot transfer to the zero address");
        if (_l1Token == address(0) && _l2Token == Predeploys.LEGACY_ERC20_ETH) {
            finalizeBridgeETH(_from, _to, _amount, _extraData);
        } else {
            finalizeBridgeERC20(_l2Token, _l1Token, _from, _to, _amount, _extraData);
        }
    }

    /// @custom:legacy
    /// @notice Retrieves the access of the corresponding L1 bridge contract.
    /// @return Address of the corresponding L1 bridge contract.
    function l1TokenBridge() external view returns (address) {
        return address(OTHER_BRIDGE);
    }

    /// @custom:legacy
    /// @notice Internal function to initiate a withdrawal from L2 to L1 to a target account on L1.
    /// @param _l2Token     Address of the L2 token to withdraw.
    /// @param _from        Address of the withdrawer.
    /// @param _to          Recipient account on L1.
    /// @param _amount      Amount of the L2 token to withdraw.
    /// @param _minGasLimit Minimum gas limit to use for the transaction.
    /// @param _extraData   Extra data attached to the withdrawal.
    function _initiateWithdrawal(
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bool _fastBridge,
        bytes memory _extraData
    )
        internal
    {
        require(_to != address(0), "L2AviBridge: cannot transfer to the zero address");
        require(paused() == false, "L2AviBridge: withdrawals are currently paused");

        address _trueTo = _to;

        // When fast bridging, the fee is collected on L1. That said, let's make sure what the users send and what they specified in _amount is the same
        if (_fastBridge) {
            require(allowedTokens[_l2Token], "L2AviBridge: token not allowed to be fast bridged");

            if (_l2Token == Predeploys.LEGACY_ERC20_ETH) {
                require(msg.value == _amount, "L2AviBridge: insufficient ETH value");
            }
            // For non-ETH tokens prevent users from sending ETH
            else {
                require(msg.value == 0, "L2AviBridge: cannot send ETH with fast bridge");
            }

            // Send the slow bridged tokens to our liquidity pool
            _trueTo = payable(liquidityPool);
        }
        // Slow withdrawals have a fee collected on L2
        else {
            // For ETH, we need to include the flat fee in the required total
            if (_l2Token == Predeploys.LEGACY_ERC20_ETH) {
                // receive() call
                if (msg.value == _amount && _amount > flatFee) {
                    _amount -= flatFee;
                }

                uint256 requiredTotal = _amount + flatFee;
                require(msg.value == requiredTotal, "L2AviBridge: insufficient ETH value");
            }
            // For ERC20 tokens, require the flat fee to be sent along with the call
            else {
                require(msg.value == flatFee, "L2AviBridge: insufficient ETH value");
            }

            (bool feeSent, ) = flatFeeRecipient.call{value: flatFee}("");
            require(feeSent, "L2AviBridge: Failed to transfer flat fee");
        }

        if (_l2Token == Predeploys.LEGACY_ERC20_ETH) {
            _initiateBridgeETH(_from, _trueTo, _amount, _minGasLimit, _extraData);
            _emitFastWithdrawlInitiated(address(0), _l2Token, _from, _to, _amount, _fastBridge, _extraData);
        } else {
            address l1Token = OptimismMintableERC20(_l2Token).remoteToken();
            _initiateBridgeERC20(_l2Token, l1Token, _from, _trueTo, _amount, _minGasLimit, _extraData);
            _emitFastWithdrawlInitiated(l1Token, _l2Token, _from, _to, _amount, _fastBridge, _extraData);
        }
    }


    function _emitFastWithdrawlInitiated(
        address l1Token,
        address l2Token,
        address from,
        address to,
        uint256 amount,
        bool fastBridge,
        bytes memory extraData
    )
        internal
    {
        if (fastBridge) {
            emit FastWithdrawalInitiated(l1Token, l2Token, from, to, amount, extraData);
        }
    }

    /// @notice Emits the legacy WithdrawalInitiated event followed by the ETHBridgeInitiated event.
    ///         This is necessary for backwards compatibility with the legacy bridge.
    /// @inheritdoc AviBridge
    function _emitETHBridgeInitiated(
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        override
    {
        emit WithdrawalInitiated(address(0), Predeploys.LEGACY_ERC20_ETH, _from, _to, _amount, _extraData);
        super._emitETHBridgeInitiated(_from, _to, _amount, _extraData);
    }

    /// @notice Emits the legacy DepositFinalized event followed by the ETHBridgeFinalized event.
    ///         This is necessary for backwards compatibility with the legacy bridge.
    /// @inheritdoc AviBridge
    function _emitETHBridgeFinalized(
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        override
    {
        emit DepositFinalized(address(0), Predeploys.LEGACY_ERC20_ETH, _from, _to, _amount, _extraData);
        super._emitETHBridgeFinalized(_from, _to, _amount, _extraData);
    }

    /// @notice Emits the legacy WithdrawalInitiated event followed by the ERC20BridgeInitiated
    ///         event. This is necessary for backwards compatibility with the legacy bridge.
    /// @inheritdoc AviBridge
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
        emit WithdrawalInitiated(_remoteToken, _localToken, _from, _to, _amount, _extraData);
        super._emitERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @notice Emits the legacy DepositFinalized event followed by the ERC20BridgeFinalized event.
    ///         This is necessary for backwards compatibility with the legacy bridge.
    /// @inheritdoc AviBridge
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
        emit DepositFinalized(_remoteToken, _localToken, _from, _to, _amount, _extraData);
        super._emitERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @notice Allows the owner to add a token to the allowedTokens mapping.
    /// @param _token Address of the token to add.
    function addAllowedToken(
        address _token
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        allowedTokens[_token] = true;
        emit AllowedTokenAdded(_token, msg.sender);
    }

    /// @notice Allows the owner to remove a token from the allowedTokens mapping.
    /// @param _token Address of the token to remove.
    function removeAllowedToken(
        address _token
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        allowedTokens[_token] = false;
        emit AllowedTokenRemoved(_token, msg.sender);
    }
}
