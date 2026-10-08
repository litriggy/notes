# 보험

스테이킹 참여자가 피보험자에게 보상 담보를 제공하고 그 대가로 수익을 얻는 프로토콜이다.

## 개요

- **피보험자**는 보상 토큰을 예치하고 보상 기간의 지급 속도를 설정한다.
- **스테이킹 참여자**는 토큰을 예치하고 지분에 따라 보상을 받는다.
- 참여자의 예치금은 담보로 쓰인다. 보험금 청구가 발생하면 스테이킹한 토큰을 피보험자에게 이전할 수 있다.
- **WithdrawDelay**는 스테이킹 출금에 시간 잠금을 적용해 필요할 때 담보를 사용할 수 있도록 한다.

## 컨트랙트

### Factory

`Stake`와 `WithdrawDelay`를 한 쌍으로 배포하고 서로 연결한다. 호출자는 두 컨트랙트의 최초 권한 보유자(auth)가 된다.

```
Factory.create(token, insuree, dur, dust, cov, epoch)
  └─► Stake
  └─► WithdrawDelay
```

### Stake

참여자는 토큰을 예치하고 지분에 비례해 보상을 받는다. 피보험자는 `inc()`로 보상 풀에 자금을 넣고 `roll()`로 보상을 연장할 수 있다.

**보상 상한**: 한 기간에 참여자에게 지급하는 보상의 상한은 `total_staked / cov`다. 초과분은 `keep`에 쌓이며 피보험자가 `refund()`로 회수한다.

**상태 전이:**

```
        stop()
Live ──────────► Stopped
                    │
           ┌────────┴────────┐
      settle(Cover)    settle(Exit)
           │                 │
           ▼                 ▼
         Cover             Exit
```

| 상태   | 설명                                     |
| ------- | ----------------------------------------------- |
| Live    | 정상 운영: 예치, 보상 적립, 출금      |
| Stopped | 보상 지급 중단, 정산 대기            |
| Cover   | 보험금 지급: 스테이킹 토큰을 피보험자에게 이전      |
| Exit    | 보험금 청구 없음: 참여자가 원금과 보상을 출금 |

**주요 함수:**

| 함수          | 호출자  | 설명                                          |
| ----------------- | ------- | ---------------------------------------------------- |
| `inc(amt)`        | 누구나  | 보상 풀에 토큰 추가, 지급 속도 증가         |
| `roll(r)`         | 피보험자 | `dur`의 후반부에 다음 기간의 지급 속도 예약  |
| `deposit(amt)`    | 참여자  | 토큰 스테이킹                                         |
| `take()`          | 참여자  | 적립된 보상 수령                                |
| `restake()`       | 참여자  | 보상을 다시 스테이킹해 복리로 운용                     |
| `stop()`          | auth    | 보상 지급 중단, keep 스냅샷 저장                        |
| `settle(s)`       | auth    | Cover 또는 Exit 상태로 전환                          |
| `cover(dst, amt)` | auth    | 스테이킹 담보를 피보험자에게 이전                |
| `exit()`          | 참여자  | 원금과 보상 출금(Exit 상태 또는 만기 후) |
| `refund()`        | 피보험자 | 상한이 적용되지 않은 보상과 keep 회수                    |

### WithdrawDelay

`Stake.withdraw()`에 2 에포크의 지연을 적용한다. 출금 대기 중인 토큰은 지연 기간이 끝날 때까지 보험금 지급 대상 담보로 남는다.

**에포크별 집계**: `stop()`은 최근 2 에포크에 출금 대기열에 들어온 총량인 `dumped`의 스냅샷을 저장한다. 보장이 유효할 때 출금한 토큰이므로 보험금 지급에 쓰일 수 있다.

**상태 전이:**

```
        stop()
Live ──────────► Stopped
                    │
           ┌────────┴────────┐
         cover()          refill()
           │                 │
           ▼                 ▼
        Covered           Refilled
```

| 상태    | `unlock()` 동작                                          |
| -------- | ------------------------------------------------------------- |
| Live     | 잠금 만료 후 해제 가능(`curr + 2 * EPOCH`)             |
| Stopped  | 잠금이 중단 에포크보다 앞서거나 dumped 토큰이 없으면 해제 가능 |
| Covered  | 중단 이전 잠금만 해제 가능(`lock.exp <= last`)           |
| Refilled | 모든 잠금 즉시 해제 가능                              |

**주요 함수:**

| 함수     | 호출자 | 설명                                         |
| ------------ | ------ | --------------------------------------------------- |
| `queue(amt)` | 참여자 | Stake에서 출금해 시간 잠금 포지션으로 이동     |
| `unlock(i)`  | 참여자 | 잠금이 만료된 토큰 수령                                |
| `stop()`     | auth   | 대기열 추가 중단, dumped 수량 스냅샷 저장              |
| `cover(dst)` | auth   | 피보험자에게 지급할 `dumped` 토큰을 Stake로 전달    |
| `refill()`   | auth   | dump를 비우고 모든 참여자의 잠금을 즉시 해제할 수 있게 처리 |

## 운영 흐름

### 정상 만기

```
피보험자  inc() ──────────────────────────────────── refund()
                                                          ▲
참여자    deposit() ──► take()/restake() ──► exit() ─────┘
```

피보험자는 `dur` 동안 지급할 보상을 마련한다. 만기가 되면 참여자는 `exit()`을 호출하고 피보험자는 `refund()`로 상한이 적용되지 않은 잔여 보상을 회수한다.

### 보험금 청구(Cover 경로)

```
피보험자  inc() ──────────────────────────── (보험금 청구)
                                                    │
auth      Stake.stop()                              │
          Stake.settle(Cover)                       │
          WithdrawDelay.stop()                      │
          WithdrawDelay.cover(dst) ────────────────►┘  dumped 토큰 → 피보험자

참여자    deposit() ──► queue() ──► unlock()  (중단 이전 잠금만)
```

1. auth가 `Stake.stop()`과 `WithdrawDelay.stop()`으로 보상 지급을 중단한다. 이때 `dumped`의 스냅샷을 저장한다.
2. auth가 `Stake.settle(Cover)`와 `WithdrawDelay.cover(dst)`로 정산한다. dumped 토큰은 `Stake.cover()`를 거쳐 피보험자에게 전달된다.
3. 중단 에포크보다 오래된 잠금은 `unlock()`으로 해제할 수 있지만 최근 2 에포크 안의 잠금은 해제할 수 없다.

### 보험금 청구 없음(Exit / Refill 경로)

```
auth      Stake.stop() ──► Stake.settle(Exit) ──► WithdrawDelay.refill()

참여자    exit()    (원금 + 보상)
          unlock()  (대기 중인 모든 포지션)
```

보험금 청구가 없으면 모든 참여자가 원금과 적립된 보상을 돌려받는다. WithdrawDelay의 모든 잠금을 즉시 해제할 수 있다.

## 보상 회계

```
topped  보상으로 예치된 토큰 총량(inc + roll)
paid    외부로 지급한 보상(take, restake, exit, refund)
keep    상한 적용으로 남은 보상 + 중단 시점에 확보한 pot

불변 조건:
  topped >= paid
  bal(Stake) >= total + topped - paid
  bal(Stake) >= total + pot + calc(all stakers)
```

보상 상한은 어느 기간에나 `rewards_to_stakers <= total_staked / cov`를 유지해 피보험자에게 지급 보상 대비 최소 보장액을 보장한다.

## 배포된 컨트랙트

```
address constant TOKEN =0xb45d2DA802eD4848A1A25755802c26303f0334e2
address constant FACTORY = 0x8aa77Cb43B32f0A0ab34a1C13d20114d36200383
address constant STAKE = 0x072090976ba290695c9871910317AC1B7d924Bb0
address constant WITHDRAW_DELAY = 0x935CF6E1854539D81ac4350eA8EBe3B7ED65d1CB
```

## 개선 사항

- 지속 운영(마지막 `inc` 시점 + `dur` 후 만료)
- 피보험자 볼트
