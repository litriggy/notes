// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Op 테스트 토큰 수령과 네트워크 설정
// 2. L1 컨트랙트 배포
// 3. L2 컨트랙트 배포
// 4. L2에서 L1 greeter 설정
// 5. L1에서 L2 greeter 설정
// 6. L2로 메시지 전송
// 7. L2에서 메시지 조회(sender = account)
// 8. L1으로 메시지 전송
// 9. L1에서 메시지 조회(sender = account)

interface ICrossDomainMessenger {
    function xDomainMessageSender() external view returns (address);
    function sendMessage(address target, bytes calldata message, uint32 gasLimit) external;
}

// 전송 L2 -> L1
// https://sepolia.etherscan.io/tx/0x55716ee249fa9c1a2125c6705434ffc1cbbda34fdeeebc1a0a5a632325b3e782
// 1. L2 Greeter.send
// 2. L1에서 메시지 증명(OptimismPortal.proveWithdrawalTransaction)
// 3. 이의 제기 기간 대기(메인넷에서는 7일)
// 4. L1에서 메시지 확정(OptimismPortal.finalizeWithdrawalTransaction)

// L1CrossDomainMessenger.sendMessage -> OptimismPortal.depositTransaction
// OptimismPortal - Sepolia
// 0x16Fc5058F25648194471939df75CF27A2fdC48BC

contract Greeter {
    // ETH Sepolia 메신저 - L1 0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef
    // OP Sepolia 메신저  - L2 0x4200000000000000000000000000000000000007
    address public immutable MESSENGER;
    // 이전 주소
    // L1 - 0x0f3ed00838a3180E32707D5997184f7AEa00433d
    // L2 - 0x034D015DBA1A960CA3b92C8d0Bd21b84fbbc507f
    // 새 주소
    // L1 - 0xCDE505e2FDaA0644cfc67D0077BEEf915D81c312
    // L2 - 0xfb471aDA6f0Cb0eb50731d8C18e2C0F2A1652466
    address public remote_greeter;
    mapping(address => string) public greetings;

    constructor(address messenger) {
        MESSENGER = messenger;
    }

    function set_remote_greeter(address _remote_greeter) external {
        remote_greeter = _remote_greeter;
    }

    function set(address sender, string memory greeting) external {
        require(msg.sender == MESSENGER, "Greeter: Caller must be the CrossDomainMessenger");
        require(
            ICrossDomainMessenger(MESSENGER).xDomainMessageSender() == remote_greeter,
            "Greeter: Remote sender must be the remote greeter"
        );

        greetings[sender] = greeting;
    }

    function send(string memory greeting) external {
        ICrossDomainMessenger(MESSENGER).sendMessage({
            target: remote_greeter,
            message: abi.encodeCall(this.set, (msg.sender, greeting)),
            // TODO: 가스 수수료
            gasLimit: 200000
        });
    }
}

// TODO: ETH에서 OP로 메시지가 어떻게 중계되는가?
// TODO: OP에서 ETH로 메시지가 어떻게 중계되는가?
// TODO: L1과 L2 사이에서 ERC20을 전송하는 방법
// TODO: L2 -> L1 트랜잭션을 직접 처리하는 방법
