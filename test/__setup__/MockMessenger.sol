// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CrossDomainMessenger } from "@eth-optimism/contracts-bedrock/src/universal/CrossDomainMessenger.sol";

contract MockMessenger is CrossDomainMessenger {
    constructor(address otherMessenger, address otherBridge) CrossDomainMessenger(address(otherMessenger)) {
        xDomainMsgSender = address(otherBridge);
    }

    event MockSendMessage(uint256 msgValue, address _to, uint64 _gasLimit, uint256 _value, bytes _data);

    function _sendMessage(
        address _to,
        uint64 _gasLimit,
        uint256 _value,
        bytes memory _data
    ) internal virtual override {
        emit MockSendMessage(msg.value, _to, _gasLimit, _value, _data);
    }

    function _isOtherMessenger()
        internal
        view
        virtual
        override
        returns (bool)
    {
        return msg.sender == address(OTHER_MESSENGER);
    }

    function _isUnsafeTarget(
        address _target
    ) internal view virtual override returns (bool) {
        return _target == address(this);
    }

    function test() public {}
}
