// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.33;

import "forge-std/Test.sol";

/*
forge test --match-path Gas.t.sol -vvv
*/

/*
# 63 / 64 가스 규칙
외부 호출에는 현재 컨트랙트에 남은 가스의 최대 63 / 64가 전달됨
가스의 1 / 64은 현재 컨트랙트에 남겨 둠

A가 B를 호출
g0 = A 안에서 gasleft()를 호출한 값
g1 = B 안에서 gasleft()를 호출한 값
g' = B 호출 직전에 실제로 남은 가스

  g'    63/64 g'
A |---->| B
|         |
g0        g1

# 사용한 가스
dg = g0와 g1 사이에 사용한 가스
   = g0와 g' 사이에 사용한 가스 + g'와 g1 사이에 사용한 가스
   = (g0 - g') + (63/64 * g' - g1)
   = g0 - 1/64 * g' - g1 >= 0

따라서
   g0 - g1 >= 1/64 * g'

# 문제
- g0 - g1을 환급하면 1/64 * g'만큼 초과 지급
- 많은 가스를 전달하면 g'를 크게 만들 수 있음

# 초과 환급 수정
g1    <= 63/64 * g' <= g0
g1/63 <=  1/64 * g' <= g0/63

g0 - g1 - g1/63 >= g0 - g1 - g'/64 >= g0 - g1 - g0/63
                                   >= 0
환급액 g0 - g1 - g1/63 = g0 - 64/63 * g1
*/

contract A {
    function f(address b) external returns (uint256, uint256, uint256) {
        uint256 gasStart = gasleft();
        (uint256 gasEnd, uint256 gasUsed) =
            B(payable(b)).g(msg.sender, gasStart);
        return (gasStart, gasEnd, gasUsed);
    }
}

contract B {
    receive() external payable {}

    function g(address receiver, uint256 gasStart)
        external
        returns (uint256, uint256)
    {
        uint256 gasNow = gasleft();

        // 가스 환급
        uint256 gasUsed = gasStart - gasNow;

        // 수정
        // uint256 gasUsed = gasStart - gasNow * 64 / 63;

        (bool ok,) = receiver.call{value: gasUsed}("");
        require(ok, "send failed");

        return (gasNow, gasUsed);
    }
}

contract GasTest is Test {
    receive() external payable {
        console.log("gas refund: %e", msg.value);
    }

    function test() public {
        A a = new A();
        B b = new B();

        address(b).call{value: 1e18}("");

        (uint256 gs1, uint256 ge1, uint256 gasUsed1) = a.f{gas: 1e6}(address(b));

        // 큰 가스 한도로 실행(전달할 가스는 <= block.gaslimit이어야 함)
        console.log("block gas limit: %e", block.gaslimit);
        (uint256 gs2, uint256 ge2, uint256 gasUsed2) = a.f{gas: 1e9}(address(b));

        // 두 번 모두 B에서 수행하는 실제 작업은 같지만
        // g'/64가 전달한 가스에 비례하므로 단순 계산한 환급액은 달라짐
        console.log("small gas refund: %e", gasUsed1);
        console.log("large gas refund: %e", gasUsed2);
        console.log("diff %e", gasUsed2 - gasUsed1);
    }
}
