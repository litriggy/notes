// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.33;

import {IERC20} from "./lib/IERC20.sol";

contract Vault {
    IERC20 public immutable token;
    // 가상 지분 오프셋(토큰 1개 = 지분 10**offset개)
    uint256 public immutable offset;
    // 사용자 => 지분
    mapping(address => uint256) public shares;
    // 총지분
    uint256 public pie;

    constructor(address _token, uint256 _offset) {
        token = IERC20(_token);
        offset = _offset;
    }

    function deposit(uint256 amt) external returns (uint256 s) {
        /*
        a = 예치할 토큰 수량
        P = 총 토큰 잔액
        s = 발행할 지분
        T = 총지분

        (P + a) / P = (T + s) / T
        a / P = s / T
        s = aT / P (P > 0이라고 가정)
        */
        uint256 bal = token.balanceOf(address(this));

        // 이 코드는 인플레이션 공격에 취약함
        // if (pie == 0) {
        //     s = amt;
        // } else {
        //     s = amt * pie / bal;
        // }

        // 가상 지분에 +10**offset
        // 가상 토큰 잔액에 +1
        s = amt * (pie + 10 ** offset) / (bal + 1);
        pie += s;
        shares[msg.sender] += s;
        token.transferFrom(msg.sender, address(this), amt);
    }

    function withdraw(uint256 s) external returns (uint256 amt) {
        /*
        a = 인출할 토큰 수량
        P = 총 토큰 잔액
        s = 소각할 지분
        T = 총지분

        (P - a) / P = (T - s) / T
        a / P = s / T
        a = Ps / T (T > 0이라고 가정)
        */
        uint256 bal = token.balanceOf(address(this));

        // 이 코드는 인플레이션 공격에 취약함
        // amt = s * bal / pie;

        amt = s * (bal + 1) / (pie + 10 ** offset);
        pie -= s;
        shares[msg.sender] -= s;
        token.transfer(msg.sender, amt);
    }
}
