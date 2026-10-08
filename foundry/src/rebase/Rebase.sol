// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.33;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {Math, RAY} from "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";

interface IMint is IERC20 {
    function mint(address dst, uint256 amt) external;
}

// 복리 이자가 쌓이는 리베이스 토큰
contract Rebase is Auth {
    using SafeTransfer for IMint;

    IMint public immutable token;
    uint256 public acc;
    uint256 public rate;
    uint256 public last;
    // 총지분
    uint256 public total;
    // 사용자 => 지분
    mapping(address => uint256) public shares;
    bool public stopped;

    modifier live() {
        require(!stopped, "stopped");
        _;
    }

    constructor(address _token) {
        token = IMint(_token);
        acc = RAY;
        rate = RAY;
        last = block.timestamp;
    }

    function set(uint256 r) external auth live {
        require(r >= RAY, "r < 1");
        sync();
        rate = r;
    }

    function calc() public view returns (uint256) {
        return acc * Math.rpow(rate, block.timestamp - last) / RAY;
    }

    function sum() external view returns (uint256) {
        return calc() * total / RAY;
    }

    function sync() public live returns (uint256 amt) {
        if (block.timestamp > last) {
            uint256 a = calc();
            acc = a;
            last = block.timestamp;
            uint256 s = a * total / RAY;
            uint256 bal = token.balanceOf(address(this));
            if (s > bal) {
                amt = s - bal;
                token.mint(address(this), amt);
            }
        }
    }

    function balance(address usr) external view returns (uint256) {
        return shares[usr] * calc() / RAY;
    }

    function join(uint256 amt) external live returns (uint256) {
        sync();
        token.transferFrom(msg.sender, address(this), amt);
        uint256 s = amt * RAY / acc;
        require(s > 0, "s = 0");
        total += s;
        shares[msg.sender] += s;
        return s;
    }

    function exit(uint256 s) external live returns (uint256) {
        sync();
        total -= s;
        shares[msg.sender] -= s;
        uint256 amt = s * acc / RAY;
        require(amt > 0, "amt = 0");
        token.transfer(msg.sender, amt);
        return amt;
    }

    function transfer(address dst, uint256 s) external live {
        shares[msg.sender] -= s;
        shares[dst] += s;
    }

    // 비율이 급증해 sync() 호출이 리버트되는 경우에 대비
    function yoink() external auth live {
        stopped = true;
        uint256 bal = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, bal);
    }
}
