// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. L1 컨트랙트 배포
// 2. L2 컨트랙트 배포
// 3. ETH 전송 L1 -> L2
// 4. L2에서 ETH 잔액 확인
// 5. L2에서 출금
// 6. ETH 전송 L2 -> L1
// 7. L1에서 ETH 잔액 확인
// 8. L1에서 출금

interface ICrossDomainMessenger {
    function xDomainMessageSender() external view returns (address);
    function sendMessage(address target, bytes calldata message, uint32 gasLimit) external payable;
}

contract Wallet {
    // ETH Sepolia 메신저 - L1 0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef
    // OP Sepolia 메신저  - L2 0x4200000000000000000000000000000000000007
    address public immutable MESSENGER;
    // L1 - 0xffC0F11c92F4E2e50b3f72Fd32BB3d034Ac77BDc
    // L2 - 0x15d97e464ed2D95cC7c7d8365681946b1d9b5DD9

    constructor(address messenger) payable {
        MESSENGER = messenger;
    }

    receive() external payable {}

    function send(address remote_wallet) external payable {
        ICrossDomainMessenger(MESSENGER).sendMessage{value: msg.value}({
            target: remote_wallet,
            message: "",
            gasLimit: 200000
        });
    }

    function get_balance() external view returns (uint256) {
        return address(this).balance;
    }

    function withdraw() external {
        (bool ok,) = msg.sender.call{value: address(this).balance}("");
        require(ok, "call failed");
    }
}
