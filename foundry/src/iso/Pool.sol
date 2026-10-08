// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.33;

import {IERC20} from "../lib/IERC20.sol";
import {SafeTransfer} from "../lib/SafeTransfer.sol";
import {
    WAD_128,
    RAY_128,
    WAD_256,
    RAY_256,
    RAD_256,
    min,
    max,
    u64,
    u128,
    mul,
    muldiv,
    pow
} from "./lib/Math.sol";

// TODO: 풀 코드 분리(pool = 불변 조건, helper = 계산)

interface IOracle {
    // coin 단위로 gem 가격 반환(1e27 -> 1e27 gem = 1e27 coin)
    // TODO: 1e27이면 소수 자릿수가 충분할까?
    function poke(address gem, address coin)
        external
        returns (bool ok, uint128 price);
}

interface IRateController {
    // [1e18], [1e18], [1e27], [timestamp] -> [1e27]
    function calc(uint128 net, uint128 debt, uint64 dt)
        external
        returns (uint128 rate);
}

// 1e18 = 100%
uint128 constant FEE = 0.05e18;
// 1e18 = 100%
uint128 constant FLASH_FEE = 0.001e18;
// 대출 대비 가치 V <= (pos.gem / (pos.debt * rac)) [1e27]
uint128 constant V = 1.5e27;
// 청산 기준 [1e27]
// 1 < 1 + 청산 보너스 < K < V
uint128 constant K = 1.1e27;
// DUST (pos.debt * rac) >= DUST
uint256 constant DUST = 100 * 1e27 * 1e18;

// TODO: 중지하고 인출?
// TODO: 청산 AMM = 오라클?
// TODO: ERC20
// TODO: 전송 수수료와 리베이스 처리?
// TODO: 소수 자릿수를 18자리로 맞출 join 어댑터?
// TODO: 프로토콜과 트레저리 수수료 분배
// TODO: 잔액 동기화 -> 프로토콜 수익

// pre = 상태 갱신 전에 수행할 계산
// post = 상태 갱신 후에 수행할 계산
// {0, 1}로 {pre, post}를 표시

// 대출 이자율
// r[i] = i <= t < i + 1인 시점 t의 대출 이자율

// 사용자가 t = K에 x를 빌렸을 때, t = K + N의 부채(pre)
// = x * (1 + r[K]) * (1 + r[K + 1]) * ... * (1 + r[K + N - 1])

// 대출 이자율 누적값
// R[0] = 1
// N > 0일 때
// R[N] = (1 + r[0]) * (1 + r[1]) * ... * (1 + r[N])

// 사용자 부채 = x * R[K + N - 1] / R[K - 1] (pre)

// 정규화한 부채
// 사용자가 시점 K에 x[0]을 빌리고 K + N에 x[1]을 빌리거나 갚았을 때, 시점 K + M의 부채(0 <= N <= M)
// = (x[0] * R[K + N - 1] / R[K - 1] + x[1]) * R[K + M - 1] / R[K + N - 1]
// = (x[0] / R[K - 1] + x[1] / R[K + N - 1]) * R[K + M - 1]
//   |____________________________________|
//              정규화한 부채

// d'[u, i] = 시점 i에 정규화한 사용자 u의 부채
// D'[i] = 시점 i에 정규화한 총부채
// D[i] = 시점 i의 총부채
//      = D'{0}[i] * R[i - 1]
//        (pre)       (pre)

// 수익(이익과 손실)
// y[i] = 시점 i - 1(post)부터 i(pre)까지의 이익 또는 손실
//      = D{0}[i] - D{1}[i - 1]
//        (pre)     (post)
//      = D'{0} * r[i - 1]

// TODO: 담보로 충당할 수 없는 손실?

// 풀 가치
// P[i] = 시점 i에 대여자에게 갚아야 할 총액(예치금 + 이자)(pre)

// post i - 1과 pre i 사이에 풀 가치가 변할 수 있음(상태 변수에 반영되지 않아도)
// P{0}[i] != P{1}[i - 1]도 가능

// 풀 성장과 대여자 지분
// g[i] = 시점 i - 1(post)부터 i(pre)까지 풀 성장률(대여자 예치금 + 이자 - 손실)
//      = (P{0}[i] - P{1}[i - 1]) / P{1}[i - 1] (P{i}[i - 1] > 0이라고 가정)
// g[0] = 1

// 대여자가 t = K에 x를 예치하고 t = K + N에 청구
// x * g[K + 1] * g[K + 2] * ... * g[K + N]

// 풀 성장 누적값
// G[0] = 1
// G[N] = g[0] * g[1] * g[2] * ... * g[N] (pre)

// 대여자가 청구할 수 있는 금액
// = x * G[K + N] / G[K]
// 대여자 지분 = x / G[K]

// 대여자 지분
// s[u, i] = 시점 i의 대여자 u의 지분
// T[i] = 시점 i의 총지분

// post i와 pre i + 1 사이에 총지분은 변하지 않음
// T{1}[i] = T{0}[i + 1]

// 대여자에게 갚아야 할 총액
// P{0}[i] = T{0}[i] * G[i]

// 수익 분배
// F = 프로토콜 수수료
// y[i] * F = 프로토콜 수익
// y[i] * (1 - F) = 대여자 수익

// 이용률
// C[i] = 시점 i에 공급한 총 coin 수량
// U[i] = 시점 i의 이용률
//      = 이자를 포함한 총부채 / (공급한 총 coin 수량 - 손실)
//      = D'{1}[i] / C{1}[i] (C{1}[i] > 0일 때)
// 이용률 -> 대출 이자율 -> 대여자 수익

// TODO: 모든 계산에 오버플로가 없는지 확인([ray] * [wad] > u128)
// TODO: rate >= 1과 rac > 0 확인

// TODO: ERC20
// TODO: 인출 대기열?
// TODO: 지분은 내림하고 부채는 올림?
// TODO: 일시적 잠금
// TODO: 부채 이자율 급증 처리
// TODO: 반올림 방향 확인(내림 = 발행, 토큰 인출; 올림 = 소각, 토큰 입금)
contract Pool {
    using SafeTransfer for IERC20;

    struct Cdp {
        // [1e18]
        uint128 col;
        // 정규화한 부채 [1e18]
        uint128 debt;
    }

    // 담보
    IERC20 public immutable gem;
    // 빌릴 토큰
    IERC20 public immutable coin;
    IOracle public immutable oracle;
    IRateController public immutable ctrl;
    // 트레저리
    address public immutable pot;

    // gem의 소수 자릿수를 1e18 기준으로 정규화
    uint128 private immutable gnorm;
    // coin의 소수 자릿수를 1e18 기준으로 정규화
    uint128 private immutable cnorm;

    // 현재 대출 이자율 r[i] [1e27]
    uint128 public rate;
    // 이자율을 마지막으로 갱신한 타임스탬프
    uint64 public last;
    // 이자율 누적값 R[N] [1e27]
    uint128 public rac;
    // 풀 성장 누적값 G[N] [1e27]
    uint128 public pac;
    // 정규화한 총부채 [1e18]
    // 이자를 포함한 총부채 = debt * rac
    uint128 public debt;
    // 차입자 => CDP
    mapping(address => Cdp) public cdps;

    // 대여자 총지분 [1e18]
    // 갚아야 할 총 coin 수량(예치금 + 이자 - 손실) = pac * pie
    uint128 public pie;
    // 대여자 지분 [1e18]
    mapping(address => uint128) public slices;
    // TODO: net * RAY <= pie * pac 확인
    // 현재 공급량(예치 - 인출 - 대출 + 상환 - 손실) [1e18]
    uint128 public net;
    // 담보로 충당할 수 없는 손실 [1e18]
    uint128 public loss;

    // 청산 버킷
    struct Bucket {
        // 담보 수량 [1e18]
        uint128 col;
        // 정규화한 부채 [1e18]
        uint128 debt;
    }
    // TODO: 슬롯의 가격 구간
    // TODO: 슬롯의 단위?
    // Slot = pos.col / pos.debt
    mapping(uint128 slot => Bucket) public buckets;

    constructor(address g, address c, address o, address r) {
        // TODO: g = c 허용?
        gem = IERC20(g);
        coin = IERC20(c);
        oracle = IOracle(o);
        ctrl = IRateController(r);
        pot = msg.sender;
        rate = RAY_128;
        rac = RAY_128;
        pac = RAY_128;
        last = u64(block.timestamp);

        uint8 gdec = gem.decimals();
        require(gdec <= 18, "gem decimals > 18");
        uint8 cdec = coin.decimals();
        require(cdec <= 18, "coin decimals > 18");
        gnorm = u128(10 ** (18 - gdec));
        cnorm = u128(10 ** (18 - cdec));
    }

    function sync() public {
        uint64 t = u64(block.timestamp);
        uint64 dt = t - last;

        // TODO: 같은 타임스탬프에 sync를 두 번 호출해도 상태 변수가 바뀌지 않는지 확인
        if (dt > 0) {
            uint128 d = debt;
            uint128 r0 = rac;

            uint256 d0 = mul(d, r0);
            // TODO: r >= 1 확인
            uint128 r = pow(rate - RAY_128, uint128(dt));
            uint128 r1 = muldiv(r0, r, RAY_128);
            /* TODO: 감소하지 않도록 강제?
            r1 = Math.max(r1, r0);
            */
            uint256 d1 = mul(d, r1);
            // y = (d1 - d0) * (1 - F) (TODO: d1 >= d0 확인)
            //   = d * (r1 - r0) * (1 - F)
            //   = d * (r0 * r - r0) * (1 - F)
            //   = d * r0 * (r - 1) * (1 - F)
            // g = y / d0
            //   = (r - 1) * (1 - F)
            uint128 g = r - RAY_128;
            uint128 fee = muldiv(g, FEE, WAD_128);
            uint128 rem = g - fee;

            // TODO: 수수료는 어떻게 처리할까?
            if (fee > 0) {
                // 트레저리에 fee * d만큼 발행?
            }

            // TODO: g > 0과 pac > 0 확인
            // TODO: rem > 0 확인
            pac = muldiv(pac, rem, RAY_128);
            rac = r1;
            last = t;
        }
    }

    function post() private {
        // TODO: rate >= 1 확인
        // uint128 r = ctrl.calc(net, Math.muldiv(debt, rac, RAY_128));
        // rate = r;
    }

    function mint(uint128 amt, uint128 min) external returns (uint128 slice) {
        sync();

        uint128 wad = amt * cnorm;
        slice = muldiv(wad, RAY_128, pac);
        require(slice >= min, "slice < min");

        pie += slice;
        slices[msg.sender] += slice;
        net += wad;

        coin.safeTransferFrom(msg.sender, address(this), amt);
        post();
    }

    function burn(uint128 slice, uint128 min) external returns (uint128 amt) {
        sync();

        uint128 wad = muldiv(slice, pac, RAY_128);
        amt = wad / cnorm;
        require(amt >= min, "amt < min");

        pie -= slice;
        slices[msg.sender] -= slice;
        net -= wad;

        coin.safeTransfer(msg.sender, amt);
        post();
    }

    function poke() public returns (uint128) {
        (bool ok, uint128 price) = oracle.poke(address(gem), address(coin));
        require(ok, "oracle not ok");
        return price;
    }

    function lock(uint128 amt) external {
        gem.safeTransferFrom(msg.sender, address(this), amt);
        cdps[msg.sender].col += amt * gnorm;
    }

    function unlock(uint128 amt) external {
        sync();

        Cdp memory cdp = cdps[msg.sender];
        cdp.col -= amt * gnorm;

        uint128 p = poke();
        require(mul(cdp.debt, rac) < mul(cdp.col, p), "unsafe cdp");

        cdps[msg.sender].col = cdp.col;
        gem.safeTransfer(msg.sender, amt);
    }

    function borrow(uint128 amt) external {
        sync();

        // TODO: amt >= min 조건 필요

        Cdp memory cdp = cdps[msg.sender];
        // TODO: amt / rac > 0 확인
        // 올림?
        uint128 wad = amt * cnorm;
        uint128 d = muldiv(wad, RAY_128, rac) + 1;
        cdp.debt += d;

        // TODO: 가격 안전 마진?
        uint128 p = poke();
        require(mul(cdp.debt, rac) < mul(cdp.col, p), "unsafe cdp");

        debt += d;
        cdps[msg.sender].debt = cdp.debt;
        net -= wad;
        coin.safeTransfer(msg.sender, amt);

        post();
    }

    function repay(uint128 amt) external {
        sync();

        Cdp memory cdp = cdps[msg.sender];
        uint128 d;
        uint128 max = muldiv(cdp.debt, rac, RAY_128) + 1;
        if (amt * cnorm >= max) {
            d = cdp.debt;
            amt = max / cnorm;
        } else {
            d = min(muldiv(amt * cnorm, RAY_128, rac) + 1, cdp.debt);
        }
        uint128 wad = amt * cnorm;
        cdp.debt -= d;
        // TODO: 최소 부채 조건 필요

        debt -= d;
        cdps[msg.sender].debt = cdp.debt;
        net += wad;
        coin.safeTransferFrom(msg.sender, address(this), amt);

        post();
    }

    // TODO: 동적 청산 비율
    // TODO: 유효한 슬롯을 여러 번 호출해도 실패하지 않아야 함
    function liquidate(
        uint128 maxCoinIn,
        uint128 minGemOut,
        uint128 slot,
        uint128 maxSlot
    ) external returns (uint128 coinAmtIn, uint128 gemAmtOut) {
        sync();

        uint128 spot = poke();
        // TODO: 잔여 소액을 상환해야 할 때 rem이 최댓값을 넘는 문제 수정
        uint128 rem = maxCoinIn * cnorm / rac;
        // 부채
        uint128 d;
        // 담보
        uint128 c;
        // 손실
        uint128 l;

        while (rem > 0 && slot <= maxSlot) {
            // 청산 조건
            // pos.col * spot / (pos.debt * rac) <= K
            require(mul(slot, spot) <= mul(K, rac), "invalid slot");
            Bucket memory buck = buckets[slot];
            // TODO:: buck.debt = 0과 buck.col = 0 처리

            // 이 버킷에서 상환할 최대 부채
            uint128 cap = min(buck.debt, rem);
            // 호출자는 잔여 소액을 남길 수 없음
            if (mul(buck.debt - cap, rac) < DUST) {
                cap = buck.debt;
            }

            // TODO: 청산 보너스 계산
            uint128 bonus = 0.05e18;

            // 상환 수량과 col 수량 계산
            // col * spot = repay * rac * (1 + bonus)
            uint128 re = cap;
            uint128 col;
            if (spot == 0) {
                col = buck.col;
                re = 0;
            } else {
                // TODO: Math로 오버플로와 정밀도 손실 처리
                //    [wad] * [ray] * [wad] / [ray] / [wad] = [wad]
                col = re * rac * (WAD_128 + bonus) / spot / WAD_128;
            }

            // col의 상한을 적용하고 상환 수량 다시 계산
            if (col > buck.col) {
                col = buck.col;
                // TODO: Math로 오버플로와 정밀도 손실 처리
                //   [wad] * [ray] * [wad] / [ray] / [wad]
                re = col * spot * WAD_128 / rac / (WAD_128 + bonus) + 1;
            }

            // TODO: re <= b.debt 확인
            // TODO: col <= b.col 확인
            Bucket storage b = buckets[slot];
            b.debt -= re;
            b.col -= col;

            d += re;
            c += col;
            // TODO: cap >= re 확인
            l += cap - re;
            // TODO: 잔여 소액 정리 시 re >= rem이 되는 문제 수정
            rem -= min(re, rem);

            // TODO: 슬롯 갱신
            // slot = 다음 슬롯
        }

        if (l > 0) {
            loss += l;
        }

        // TODO: net 갱신?

        // coinAmtIn = d * rac / RAY / cnorm + 1;
        // gemAmtOut = c / gnorm;

        require(coinAmtIn <= maxCoinIn, "coin in > max");
        require(gemAmtOut >= minGemOut, "gem out < min");
        coin.safeTransferFrom(msg.sender, address(this), coinAmtIn);
        gem.safeTransfer(msg.sender, gemAmtOut);
    }

    function flash(uint128 c, uint128 g) external {}

    function donate(uint128 amt) external {
        loss -= amt * cnorm;
        coin.safeTransferFrom(msg.sender, address(this), amt);
    }
    // TODO: 권한 검사 후 매개변수 설정(K, V, LIQ_MIN_BONUS, LIQ_MAX_BONUS)
    // TODO: 일시 중지
    // TODO: 긴급 복구
    // TODO: 잔여 소액을 트레저리로 이동
}

// TODO: 가격 구간 또는 연결 리스트?
// 이중 연결 리스트 <- 버킷을 유용하게 쓰려면 여전히 압축 필요
// 삽입     O(N)
// 삭제     O(1)
// 갱신(삭제 + 삽입) O(1) + O(N)
// 최상단 찾기 O(1)

// 가격 구간
//             [wad] * [ray] / [wad]
// C * slot <= pos.col * RAY / pos.debt < C * slot + 1
// slot = pos.col * RAY / pos.debt / C

// 압축
// C가 작음 -> 슬롯이 드문드문 분포
// C가 큼 -> 넓은 가격 범위를 하나의 슬롯으로 묶음
//                        C = 10 | 100
// 1 * 100 / 10 = 10 / C   |  1  |   0
// 2 * 100 / 10 = 20 / C   |  2  |   0
// 3 * 100 / 10 = 30 / C   |  3  |   0
// 11 * 100 / 10 = 110 / C | 11  |   1

//        [1e18] * [1e27] / [1e18] = [1e27] / [C]
// slot = pos.col * RAY / pos.debt / C

// 청산 가격
// pos.col * spot <= K * pos.debt * rac

// Uniswap v3 틱
//                2.94e-39부터 3.4e38까지
// tick = int24 (-8,388,608부터 +8,388,607까지)

// 슬롯 정밀도
// 1 slot = 1e18
// 0 <= slot <= 1e18
// slot <= 1e18 * [1e18] < 2**128
