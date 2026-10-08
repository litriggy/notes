// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.33;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {Math} from "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";

contract Stake is Auth {
    using SafeTransfer for IERC20;

    event Deposit(address indexed usr, uint256 amt);
    event Withdraw(address indexed usr, uint256 amt);
    event Take(address indexed usr, uint256 amt);
    event Refund(address indexed usr, uint256 amt);
    event Restake(address indexed usr, uint256 amt);
    event Inc(uint256 amt);
    event Roll(uint256 rate);
    event Stop();
    event Settle(uint256 state);
    event Cover(uint256 amt);
    event Exit(address indexed usr, uint256 amt);

    // 비율 스케일
    uint256 private constant R = 1e9;
    IERC20 public immutable token;
    // 보상 기간
    uint256 public immutable dur;
    // 최소 예치 수량이자 스테이킹 상태로 유지해야 하는 최소 수량
    uint256 public immutable dust;
    // 목표 보장 비율
    // 기간 내 지급한 총보상 <= min(기간에 배정한 총보상, 총스테이킹 수량의 최댓값 / cov)
    uint256 public immutable cov;

    enum State {
        Live,
        Stopped,
        Cover,
        Exit
    }

    State public state;

    // 총스테이킹 수량
    uint256 public total;
    // 사용자 => 스테이킹 수량
    mapping(address usr => uint256 amt) public shares;

    // 마지막 갱신 시각
    uint256 public last;
    // 만료 시각
    uint256 public exp;
    // 초당 토큰 지급 속도
    uint256 public rate;
    // 비율 누적값
    uint256 public acc;
    // 사용자 => 마지막 비율 누적값
    mapping(address usr => uint256 acc) public accs;
    mapping(address usr => uint256 amt) public rewards;

    // 다음 비율
    uint256 public nextRate;
    // 다음 비율을 적용할 타임스탬프
    uint256 public next;
    // roll을 호출할 권한이 있는 계정
    address public insuree;

    // stop 이후 남은 보상
    uint256 public keep;
    // 예치한 총보상
    uint256 public topped;
    // 청구한 총보상(외부 전송 또는 재스테이킹)
    uint256 public paid;

    modifier live() {
        require(state == State.Live, "not live");
        require(block.timestamp < exp, "expired");
        _;
    }

    constructor(
        address _token,
        address _insuree,
        uint256 _dur,
        uint256 _dust,
        uint256 _cov
    ) {
        token = IERC20(_token);
        insuree = _insuree;
        dur = _dur;
        dust = _dust;
        cov = _cov;
        state = State.Live;
        last = block.timestamp;
        exp = block.timestamp + _dur;

        require(cov >= 1 && cov <= 1000, "invalid cov");
        // tot > 0일 때 cap() > 0인지 확인
        require(dust * R >= cov * dur, "dust < cov * dur");

        // 아무도 스테이킹하지 않은 동안 피보험자가 보상을 회수할 수 있음
        // 이 지분을 반영하기 위해 일부 계산에 total + 1 사용
        shares[address(this)] = 1;
    }

    function stopped() external view returns (bool) {
        return state != State.Live;
    }

    // 남은 보상
    function pot() public view returns (uint256 rem) {
        if (exp <= block.timestamp) {
            return 0;
        }
        if (next > 0) {
            if (block.timestamp < next) {
                rem = rate * (next - block.timestamp) / R;
                rem += nextRate * dur / R;
            } else if (block.timestamp < exp) {
                rem = nextRate * (exp - block.timestamp) / R;
            }
        } else {
            if (block.timestamp < exp) {
                rem = rate * (exp - block.timestamp) / R;
            }
        }
    }

    // 비율의 상한
    // a = 해당 기간에 배정한 총보상
    // 총스테이킹 수량 <= cov * a이면
    // 지급한 총보상 <= 총스테이킹 수량 / cov
    // c = cap으로 둠
    // sum(c * dt) <= sum(r * dt) <= a
    // 전체 기간 동안 total <= cov * a이면
    // total / cov / dur <= a / dur <= rate, inc() 이후에는 rate가 항상 증가하기 때문
    // sum(c * dt) <= total / cov / dur * sum(dt) = total / cov
    function cap(uint256 r, uint256 tot) private view returns (uint256) {
        return Math.min(r, tot * R / (cov * dur));
    }

    // 사용자가 청구할 수 있는 보상 계산
    function calc(address usr) external view returns (uint256) {
        // 타임스탬프의 상한을 exp로 제한
        uint256 t = Math.min(block.timestamp, exp);
        uint256 a = acc;
        uint256 tot = total;
        if (next > 0 && next <= t) {
            a += cap(rate, tot) * (next - last) / (tot + 1);
            a += cap(nextRate, tot) * (t - next) / (tot + 1);
        } else {
            a += cap(rate, tot) * (t - last) / (tot + 1);
        }
        return rewards[usr] + shares[usr] * (a - accs[usr]) / R;
    }

    // 보상 동기화
    function sync(address usr) public returns (uint256 amt) {
        // 타임스탬프의 상한을 exp로 제한
        uint256 t = Math.min(block.timestamp, exp);
        uint256 a = acc;
        uint256 tot = total;
        // 초과분을 피보험자 몫으로 저장
        uint256 saved = 0;

        if (next > 0 && next <= t) {
            uint256 r = rate;
            uint256 c = cap(r, tot);
            uint256 dt = next - last;
            a += c * dt / (tot + 1);
            saved += (r - c) * dt / R;

            last = next;
            rate = nextRate;
            nextRate = 0;
            next = 0;
        }

        uint256 r = rate;
        uint256 c = cap(r, tot);
        uint256 dt = t - last;
        a += c * dt / (tot + 1);
        saved += (r - c) * dt / R;

        acc = a;
        last = t;

        if (saved > 0) {
            keep += saved;
        }

        if (usr != address(0)) {
            amt = shares[usr] * (a - accs[usr]) / R;
            accs[usr] = a;
            rewards[usr] += amt;
        }
    }

    function deposit(uint256 amt) external live {
        require(amt >= dust, "dust");
        token.safeTransferFrom(msg.sender, address(this), amt);
        sync(msg.sender);
        total += amt;
        shares[msg.sender] += amt;
        emit Deposit(msg.sender, amt);
    }

    function withdraw(address usr, address dst, uint256 amt)
        external
        auth
        live
    {
        require(usr != address(this), "invalid usr");
        sync(usr);
        total -= amt;
        shares[usr] -= amt;
        require(shares[usr] == 0 || shares[usr] >= dust, "dust");
        token.safeTransfer(dst, amt);
        emit Withdraw(usr, amt);
    }

    // 보상 청구
    function take() public returns (uint256 amt) {
        sync(msg.sender);
        amt = rewards[msg.sender];
        if (amt > 0) {
            rewards[msg.sender] = 0;
            paid += amt;
            token.safeTransfer(msg.sender, amt);
        }
        emit Take(msg.sender, amt);
    }

    // 보상 재스테이킹
    function restake() external live returns (uint256 amt) {
        sync(msg.sender);
        amt = rewards[msg.sender];
        if (amt > 0) {
            rewards[msg.sender] = 0;
            paid += amt;
            total += amt;
            shares[msg.sender] += amt;
            require(shares[msg.sender] >= dust, "dust");
        }
        emit Restake(msg.sender, amt);
    }

    // 피보험자에게 환급
    function refund() external returns (uint256 amt) {
        require(msg.sender == insuree, "not insuree");

        sync(address(this));
        amt = rewards[address(this)];
        if (amt > 0) {
            rewards[address(this)] = 0;
            paid += amt;
        }

        if (keep > 0) {
            amt += keep;
            paid += keep;
            keep = 0;
        }

        if (amt > 0) {
            token.safeTransfer(msg.sender, amt);
        }
        emit Refund(msg.sender, amt);
    }

    // 보상 지급 속도 증가
    function inc(uint256 amt) external live {
        sync(address(0));
        token.safeTransferFrom(msg.sender, address(this), amt);

        uint256 t = next > 0 ? next : exp;
        uint256 delta = amt / (t - block.timestamp);
        require(delta > 0, "delta rate = 0");
        rate += delta * R;
        topped += amt;

        emit Inc(amt);
    }

    // 보험 기간 연장 및 새 비율 적용 예약
    function roll(uint256 r) external live {
        require(msg.sender == insuree, "not insuree");
        require(rate > 0, "rate = 0");
        require(next == 0, "rolled");
        // 남은 시간이 전체 기간의 절반 미만이면 연장 허용
        require(exp - block.timestamp < dur / 2, "too early");

        sync(address(0));
        if (r > 0) {
            uint256 amt = r * dur;
            token.safeTransferFrom(msg.sender, address(this), amt);
            topped += amt;
        }

        nextRate = r * R;
        next = exp;
        exp += dur;

        emit Roll(r);
    }

    // 보상 지급 중지
    function stop() external auth live {
        sync(address(0));
        keep += pot();
        exp = block.timestamp;
        state = State.Stopped;
        emit Stop();
    }

    // 지급 대상 결정(피보험자 또는 스테이킹 참여자)
    function settle(State s) external auth {
        require(state == State.Stopped, "not stopped");
        require(s == State.Cover || s == State.Exit, "invalid next state");
        state = s;
        emit Settle(uint256(s));
    }

    // 피보험자에게 지급
    function cover(address dst, uint256 amt) external auth returns (uint256) {
        require(state == State.Cover, "invalid state");
        require(dst != address(0), "dst = 0");

        if (amt > 0) {
            token.safeTransferFrom(msg.sender, address(this), amt);
        }

        amt += total;
        total = 0;

        token.safeTransfer(dst, amt);

        emit Cover(amt);
        return amt;
    }

    // 스테이킹 참여자에게 지급
    function exit() external returns (uint256 amt) {
        // stop 호출 없이 만료되었거나 정산 완료
        if (state == State.Live) {
            require(exp < block.timestamp, "not expired");
        } else {
            require(state == State.Exit, "invalid state");
        }

        sync(msg.sender);

        // 보상
        uint256 r = rewards[msg.sender];
        rewards[msg.sender] = 0;
        paid += r;

        // 스테이킹 수량
        uint256 s = shares[msg.sender];
        shares[msg.sender] = 0;
        total -= s;

        amt = r + s;

        token.safeTransfer(msg.sender, amt);

        emit Exit(msg.sender, amt);
    }

    function recover(address _token) external auth {
        if (_token == address(0)) {
            (bool ok,) = msg.sender.call{value: address(this).balance}("");
            require(ok, "send ETH failed");
        } else if (_token == address(token)) {
            uint256 bal = token.balanceOf(address(this));
            // topped >= paid
            // topped - paid = 앞으로 지급할 보상 + 스테이킹 참여자가 청구할 수 있는 보상
            // bal >= staked + topped - paid
            uint256 need = total + topped - paid;
            token.safeTransfer(msg.sender, bal - need);
        } else {
            uint256 bal = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, bal);
        }
    }
}
