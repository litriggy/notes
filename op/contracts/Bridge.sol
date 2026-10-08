// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// L1    | L2
// ERC20 | OPERC20 (OptimismMintableERC20)

// L1에서 L2로 ERC20 전송
// L1StandardBrige에 ERC20 잠금
// -> CrossDomainMessenger (L1)
// -> L2StandardBrige (L2)
// -> OPERC20 발행(L2)

// L2에서 L1으로 ERC20 전송
// L2StandardBrige에서 OPERC20 소각
// -> CrossDomainMessenger (L2)
// -> L1StandardBridge의 ERC20 잠금 해제

// 1. L1에 ERC20 배포
// 2. L2에 OPERC20 배포
// 3. L1에 L1Bridge 배포
// 4. L2에 L2Bridge 배포
// 5. ERC20 발행 후 L1Bridge에 사용 승인
// 6. L2로 ERC20 전송
// 7. L2Bridge의 OPERC20 잔액 확인
// 8. L2에서 OPERC20 출금
// 9. L2Bridge에 OPERC20 사용 승인 후 L1으로 ERC20 전송
// 10. L1Bridge의 ERC20 잔액 확인
// 11. L1에서 ERC20 출금
// 12. 확정 트랜잭션과 토큰 전송 확인

interface IL1StandardBridge {
    // bridgeERC20To와 같은 내부 함수 호출
    function depositERC20To(
        address l1_token,
        address l2_token,
        address to,
        uint256 amount,
        uint32 min_gas_limit,
        bytes calldata data
    ) external;

    function bridgeERC20To(
        address local_token,
        address remote_token,
        address to,
        uint256 amount,
        uint32 min_gas_limit,
        bytes calldata data
    ) external;
}

interface IL2StandardBridge {
    // bridgeERC20To와 같은 내부 함수 호출
    function withdrawTo(address l2_token, address to, uint256 amount, uint32 min_gas_limit, bytes calldata data)
        external;

    function bridgeERC20To(
        address local_token,
        address remote_token,
        address to,
        uint256 amount,
        uint32 min_gas_limit,
        bytes calldata data
    ) external;
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
}

// 0xB0b0F34273940594b6E637Ca9e8fdc527061c423
contract L1Bridge {
    // 0xFBb0621E0B23b5478B630BD55a5f21f67730B0F1
    address public immutable l1_op_bridge;
    // 0x93F74d0730758094cE8Cb2ee1f6999A7cD38e75a 
    address public immutable l1_token;
    // 0x27d48bDF3238DFd85023139f0400eFa4B646b474
    address public immutable l2_token;

    constructor(address _l1_op_bridge, address _l1_token, address _l2_token) {
        l1_op_bridge = _l1_op_bridge;
        l1_token = _l1_token;
        l2_token = _l2_token;

        // TODO: 무제한 사용 승인은 안전한가?
        IERC20(l1_token).approve(l1_op_bridge, type(uint256).max);
    }

    // 입금 L1 -> L2
    // remote_addr = L2Bridge
    function sendToL2(address remote_addr, uint256 amount) external {
        // TODO: 브리지 전송은 어떻게 취소하는가?
        IERC20(l1_token).transferFrom(msg.sender, address(this), amount);
        IL1StandardBridge(l1_op_bridge).bridgeERC20To({
            local_token: l1_token,
            remote_token: l2_token,
            to: remote_addr,
            amount: amount,
            // TODO: 여기에 어떤 값을 넣어야 하는가?
            min_gas_limit: 200000,
            data: ""
        });
    }

    function withdraw(address token) external {
        uint256 bal = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(msg.sender, bal);
    }
}

// 0x31B136e2d1fa077e6e6b629b05B1E0360835e5B8
// L2에서 L1으로 출금하는 트랜잭션
// https://optimism-sepolia.blockscout.com/tx/0x915f467d322682f0bb1bfe332a9099dcef8dbd2acc4335b0d653cb5d255b655b
contract L2Bridge {
    // 0x4200000000000000000000000000000000000010
    address public immutable l2_op_bridge;
    address public immutable l1_token;
    address public immutable l2_token;

    constructor(address _l2_op_bridge, address _l1_token, address _l2_token) {
        l2_op_bridge = _l2_op_bridge;
        l1_token = _l1_token;
        l2_token = _l2_token;

        // TODO: 무제한 사용 승인은 안전한가?
        IERC20(l2_token).approve(l2_op_bridge, type(uint256).max);
    }

    // 출금 L2 -> L1
    // remote_addr = L1Bridge
    function sendToL1(address remote_addr, uint256 amount) external {
        // TODO: 브리지 전송은 어떻게 취소하는가?
        IERC20(l2_token).transferFrom(msg.sender, address(this), amount);
        IL1StandardBridge(l2_op_bridge).bridgeERC20To({
            local_token: l2_token,
            remote_token: l1_token,
            to: remote_addr,
            amount: amount,
            // TODO: 여기에 어떤 값을 넣어야 하는가?
            min_gas_limit: 200000,
            data: ""
        });
    }

    function withdraw(address token) external {
        uint256 bal = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(msg.sender, bal);
    }
}
