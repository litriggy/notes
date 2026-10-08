// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";

contract FalseArrLenTest is Test {
    function f(uint256 len) public pure returns (uint256[] memory arr) {
        assembly {
            arr := mload(0x40)
            mstore(arr, len)
            // 빈 메모리 포인터를 옮겨 가짜 길이만큼 공간 확보
            mstore(0x40, add(arr, 32))
        }
    }

    function test() public {
        // 내부 호출은 정상 동작
        uint256[] memory arr = f(type(uint256).max);

        // 외부 호출은 리버트(가스 부족)
        // uint256[] memory arr = this.f(type(uint256).max);

        // 빈 메모리 포인터를 갱신하지 않으면
        // console.log가 arr와 같은 메모리에 기록하므로
        // 길이는 새 변수에 저장
        uint256 len = arr.length;
        console.log("arr length:", len);
    }
}
