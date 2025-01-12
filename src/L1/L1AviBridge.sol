// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AviPredeploys } from "src/libraries/AviPredeploys.sol";
import { AviBridge } from "src/universal/AviBridge.sol";
import { CrossDomainMessenger } from "@eth-optimism/contracts-bedrock/src/universal/CrossDomainMessenger.sol";
import { LiquidityPool } from "src/L1/LiquidityPool.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SafeCall } from "@eth-optimism/contracts-bedrock/src/libraries/SafeCall.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

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
contract L1AviBridge is AviBridge {
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

    /// @notice Emitted whenever Bridging fee is set.
    /// @param previousFee       uint256 of old fee.
    /// @param fee               uint256 of new fee.
    /// @param executedBy        address of calling address.
    event BridgingFeeChanged(
        uint256 previousFee,
        uint256 fee,
        address executedBy
    );

    /// @notice Emitted whenever Avi token address is set.
    /// @param previousAviTokenAddress      address of old avi Token.
    /// @param aviTokenAddress              address of new avi Token.
    /// @param executedBy                   address of calling address.
    event AviTokenAddressChanged(
        address previousAviTokenAddress,
        address aviTokenAddress,
        address executedBy
    );

    /// @notice Emitted whenever Optimism Portal is changed.
    /// @param previousPortal Address of the old Optimism portal that was used.
    /// @param portal Address of the new Optimism portal to be used.
    /// @param executedBy Address of the caller.
    event OptimismPortalChanged(
        address previousPortal,
        address portal,
        address executedBy
    );

    /// @notice Emitted whenever tokens are fast withdrawn.
    /// @param amount       uint256 of the amount.
    /// @param l1Token      address of the token on L1.
    /// @param to           address of the recipient.
    /// @param executedBy   address of the caller.
    event FastWithdraw(
        uint256 amount,
        address l1Token,
        address to,
        address executedBy,
        uint64 l2_block_number
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
    string public constant version = "1.5.0";

    /// @notice The numerator component of the percentage based briding fee for all deposits.
    uint256 public bridgingFee;

    /// @notice the liquidity pool
    LiquidityPool public LIQUIDITY_POOL;

    /// @notice The address of the Aviator token on the L1 chain
    address public L1AviToken;

    /// @notice Fastwithdrawal nonces
    mapping(address => uint256) private fastBridgeNonces;

    /// @notice Fastwithdrawal request structure
    struct AviFastWithdrawal {
        address verifying_contract;

        address l1_token;
        address l2_token;
        address from;
        address to;
        uint256 amount;
        uint256 nonce;
        uint64 l2_block_number;

        bytes proof_transaction;
    }

    bytes32 private constant _WITHDRAWAL_TYPEHASH = keccak256("AviFastWithdrawal(address verifying_contract,address l1_token,address l2_token,address from,address to,uint256 amount,uint256 nonce,uint64 l2_block_number,bytes proof_transaction)");
    bytes32 private constant _EIP712_DOMAIN = keccak256("EIP712Domain(string name,string version,address verifyingContract)");
    bytes32 private constant _EIP712_NAME = keccak256("SkyBridge");
    bytes32 private constant _EIP712_VERSION = keccak256("1");

    /// @notice the OptimismPortal contract address
    address payable public optimismPortal;

    event SupersonicFeeChanged(
        uint256 previousFee,
        uint256 fee,
        address executedBy
    );

    uint256 public supersonicFee;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(bool isTestMode) {
        // isTestMode is used to disable the disabling of the initializers when running tests
        if (!isTestMode) {
            _disableInitializers();
        }
    }

    function initialize(
        // Optimism stack first
        address payable _L1CrossDomainMessenger,
        address payable _optimismPortal,
        // AVI stack after
        address payable _liquidityPool,
        address _token
    ) public initializer {
        require(_L1CrossDomainMessenger != address(0), "AviBridge: L1CrossDomainMessenger address cannot be zero");
        require(_optimismPortal != address(0), "AviBridge: OptimismPortal address cannot be zero");

        require(_liquidityPool != address(0), "AviBridge: LiquidityPool address cannot be zero");
        require(_token != address(0), "AviBridge: Avi L1 Token address cannot be zero");

        __SkyBridge_init(_L1CrossDomainMessenger, payable(AviPredeploys.L2_STANDARD_BRIDGE));

        optimismPortal = _optimismPortal;

        LIQUIDITY_POOL = LiquidityPool(_liquidityPool);
        L1AviToken = _token;

        flatFeeRecipient = _liquidityPool;

        bridgingFee = 3;

        supersonicFee = 0.005 ether;
    }

    /// @notice Updates the numerator component of the percentage based bridging fee for all deposits.
    /// @param _fee New numerator component of the percentage based bridging fee.
    function setBridgingFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_fee <= 100, "AviBridge: _fee must be less than or equal to 100");

        uint256 previousBridgingFee = bridgingFee;

        bridgingFee = _fee;

        emit BridgingFeeChanged(previousBridgingFee, bridgingFee, msg.sender);
    }

    /// @notice Updates the supersonic fee for all withdrawals.
    /// @param _fee New supersonic fee.
    function setSupersonicFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_fee <= 0.005 ether, "AviBridge: _fee must be less than or equal to 0.005 ether");

        uint256 previousSupersonicFee = supersonicFee;
        supersonicFee = _fee;

        emit SupersonicFeeChanged(previousSupersonicFee, supersonicFee, msg.sender);
    }

    /// @notice Sets the address for the Avi L1 token so that it may avoid fees
    /// @param _token Address of the token contract
    function setAviTokenAddress(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(0), "AviBridge: _token address cannot be zero");

        address _previousL1AviToken = L1AviToken;

        L1AviToken = _token;

        emit AviTokenAddressChanged(_previousL1AviToken, L1AviToken, msg.sender);
    }

    /// Sets the Optimism portal to use for this bridge
    /// @param _portal Address of the portal contract
    function setOptimismPortal(address payable _portal) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_portal != address(0), "AviBridge: _portal cannot be zero");

        address _previousPortal = optimismPortal;

        optimismPortal = _portal;

        emit OptimismPortalChanged(_previousPortal, optimismPortal, msg.sender);
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
        require(_to != address(0), "ETH: transfer to the zero address");
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
        require(_to != address(0), "ERC20: transfer to the zero address");
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

    /// @notice Fast withdraw ETH or ERC20 from the bridge.
    /// @param _txn The signed transation message
    /// @param _signature The signature of the transaction
    function fastWithdraw(
        AviFastWithdrawal calldata _txn,
        bytes calldata _signature
    )
        external
        payable
    {
        require(paused() == false, "L1AviBridge: fast withdrawals are currently paused");
        require(backendUser != address(0), "L1AviBridge: invalid backend user");
        // Temporarily needed until we configure the field. The alternative would have been to set it to the initial value of
        // 0.005 ETH, but this feels safer
        require(supersonicFee > 0, "L1AviBridge: fast withdrawals are not fully configured");

        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        bytes32 structHash = keccak256(
            abi.encode(
                _WITHDRAWAL_TYPEHASH,
                _txn.verifying_contract,
                _txn.l1_token,
                _txn.l2_token,
                _txn.from,
                _txn.to,
                _txn.amount,
                _txn.nonce,
                _txn.l2_block_number,
                keccak256(_txn.proof_transaction)
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                _EIP712_DOMAIN,
                _EIP712_NAME,
                _EIP712_VERSION,
                _txn.verifying_contract
            )
        );

        address signer = ECDSA.recover(
            ECDSA.toTypedDataHash(domainSeparator, structHash),
            v,
            r,
            s
        );

        require(signer == backendUser, "invalid signature");
        require(fastBridgeNonces[_txn.from] == _txn.nonce, "invalid nonce");

        require(msg.value == supersonicFee, "AviBridge: insufficient value for fee");

        (bool feeSent, ) = address(flatFeeRecipient).call{value: supersonicFee}("");
        require(feeSent, "AviBridge: failed to send fee");

        fastBridgeNonces[_txn.from] += 1;

        // Transfer the tokens, ETH if the l1_token is address(0)
        if (_txn.l1_token == address(0)) {
            LIQUIDITY_POOL.sendETH(_txn.to, _txn.amount);
        } else {
            LIQUIDITY_POOL.sendERC20(_txn.to, _txn.l1_token, _txn.amount);
        }

        bool success = SafeCall.call(optimismPortal, gasleft(), 0, _txn.proof_transaction);
        require(success, "AviBridge: failed to prove transaction to Optimism Portal");

        emit FastWithdraw(_txn.amount, _txn.l1_token, _txn.to, msg.sender, _txn.l2_block_number);
    }

    /// @notice Internal function for initiating an ETH deposit.
    /// @param _from        Address of the sender on L1.
    /// @param _to          Address of the recipient on L2.
    /// @param _minGasLimit Minimum gas limit for the deposit message on L2.
    /// @param _extraData   Optional data to forward to L2.
    function _initiateETHDeposit(address _from, address _to, uint32 _minGasLimit, bytes memory _extraData) internal {
        require(paused() == false, "L1AviBridge: deposits are currently paused");

        // At least flatFee is required
        require(msg.value > flatFee, "AviBridge: insufficient ETH value");

        // Calculate the bridgingFee for the remainder
        uint256 remainingValue = msg.value - flatFee;
        uint256 bridgeFee = (remainingValue * bridgingFee) / 1000;

        // Must send in total at least this much ETH to deposit
        uint256 totalFee = flatFee + bridgeFee;

        // We check that the user sent more than the total fee so they bridge *something*
        require(msg.value > totalFee, "AviBridge: insufficient ETH value");

        uint256 _amount = msg.value - totalFee;

        // Transfer the flat fee to the flat fee recipient
        (bool sentToFlatFee, ) = payable(flatFeeRecipient).call{value: flatFee}("");
        require(sentToFlatFee, "AviBridge: transfer of flat fee to flat fee pool failed");

        // Transfer the bridging fee to the liquidity pool
        (bool sentToLiquidityPool, ) = payable(LIQUIDITY_POOL).call{value: bridgeFee}("");
        require(sentToLiquidityPool, "AviBridge: transfer of bridging fee to liquidity pool failed");

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
        require(paused() == false, "L1AviBridge: deposits are currently paused");

        require(msg.value == flatFee, "AviBridge: bridging ERC20 must include sufficient ETH value");

        (bool sent, ) = payable(flatFeeRecipient).call{value: msg.value}("");
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

    /// @notice Get the current nonce for the fast withdrawal
    function getNonce() public view returns (uint256) {
        return fastBridgeNonces[msg.sender];
    }

    /// @notice Splits an EIP-712 signature into r, s, and v components.
    /// @param signature The EIP-712 signature.
    function splitSignature(bytes memory signature) internal virtual returns (bytes32 r, bytes32 s, uint8 v) {
        require(signature.length == 65, "invalid signature length");
        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(signature, 32))
            // second 32 bytes
            s := mload(add(signature, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(signature, 96)))
        }
    }
}
