// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.33;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {Auth} from "../lib/Auth.sol";
import {IStake} from "./lib/IStake.sol";

contract WithdrawDelay is Auth {
    using SafeTransfer for IERC20;

    event Queue(address indexed usr, uint256 i, uint256 amt);
    event Unlock(address indexed usr, uint256 i, uint256 amt);
    event Stop(uint256 amt);

    IERC20 public immutable token;
    IStake public immutable stake;
    // 에포크 길이
    uint256 public immutable EPOCH;

    enum State {
        Live,
        Stopped,
        Covered,
        Refilled
    }

    State public state;

    struct Lock {
        uint256 amt;
        uint256 exp;
    }

    // 사용자 => 잠금 개수
    mapping(address usr => uint256 count) public counts;
    // 사용자 => 잠금 인덱스 => Lock
    mapping(address usr => mapping(uint256 i => Lock)) public locks;
    // 대기 중인 총수량
    uint256 public keep;

    // 마지막으로 갱신한 에포크
    uint256 public last;
    // 최근 2개 에포크에서 대기 중인 총수량
    uint256[2] public buckets;
    // 배출한 총수량
    uint256 public dumped;

    constructor(address _stake, uint256 _epoch) {
        stake = IStake(_stake);
        token = IERC20(stake.token());
        EPOCH = _epoch;
        state = State.Live;
        last = (block.timestamp / EPOCH) * EPOCH;
    }

    modifier live() {
        require(state == State.Live, "not live");
        _;
    }

    function stopped() external view returns (bool) {
        return state != State.Live;
    }

    function queue(uint256 amt) external live returns (uint256 i) {
        require(amt > 0, "amt = 0");

        stake.withdraw(msg.sender, address(this), amt);
        keep += amt;

        // 현재 에포크
        uint256 curr = (block.timestamp / EPOCH) * EPOCH;
        // 다음 에포크의 끝
        uint256 exp = curr + 2 * EPOCH;

        // 버킷 갱신
        if (last + 2 * EPOCH <= curr) {
            buckets[0] = 0;
            buckets[1] = 0;
        } else if (last + EPOCH == curr) {
            buckets[0] = buckets[1];
            buckets[1] = 0;
        }

        buckets[1] += amt;
        last = curr;

        i = counts[msg.sender];
        locks[msg.sender][i] = Lock({amt: amt, exp: exp});
        counts[msg.sender] = i + 1;

        emit Queue(msg.sender, i, amt);
    }

    function unlock(uint256 i) external {
        require(i < counts[msg.sender], "index out of bound");
        Lock storage lock = locks[msg.sender][i];
        require(lock.amt > 0, "lock amt = 0");

        State s = state;
        if (s == State.Live) {
            require(lock.exp <= block.timestamp, "lock not expired");
        } else if (s == State.Stopped) {
            require(lock.exp <= last || dumped == 0, "cannot unlock");
        } else if (s == State.Covered) {
            require(lock.exp <= last, "dumped");
        }
        // 다시 채워짐 - 모든 잠금 만료

        uint256 amt = lock.amt;
        keep -= amt;
        delete locks[msg.sender][i];

        token.safeTransfer(msg.sender, amt);

        emit Unlock(msg.sender, i, amt);
    }

    function stop() external auth live returns (uint256 amt) {
        state = State.Stopped;

        uint256 curr = (block.timestamp / EPOCH) * EPOCH;

        if (last + 2 * EPOCH <= curr) {
            buckets[0] = 0;
            buckets[1] = 0;
        } else if (last + EPOCH == curr) {
            buckets[0] = buckets[1];
            buckets[1] = 0;
        }

        last = curr;
        amt = buckets[0] + buckets[1];

        if (amt > 0) {
            buckets[0] = 0;
            buckets[1] = 0;
            dumped = amt;
        }

        emit Stop(amt);
    }

    function cover(address dst) external auth {
        require(state == State.Stopped, "not stopped");
        require(stake.state() == IStake.State.Cover, "invalid state");
        state = State.Covered;

        uint256 amt = dumped;
        if (amt > 0) {
            keep -= amt;
            dumped = 0;
            token.approve(address(stake), amt);
        }
        stake.cover(dst, amt);
    }

    function refill() external auth {
        require(state == State.Stopped, "not stopped");
        require(stake.state() == IStake.State.Exit, "invalid state");
        state = State.Refilled;
        dumped = 0;
    }

    function recover(address _token) external auth {
        if (_token == address(0)) {
            (bool ok,) = msg.sender.call{value: address(this).balance}("");
            require(ok, "send ETH failed");
        } else if (_token == address(token)) {
            uint256 bal = token.balanceOf(address(this));
            token.safeTransfer(msg.sender, bal - keep);
        } else {
            uint256 bal = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, bal);
        }
    }
}
