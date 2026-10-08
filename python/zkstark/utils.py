import hashlib
import math
import random


def fiat_shamir(s: str) -> int:
    h = hashlib.sha256(s.encode()).digest()
    return int.from_bytes(h, "big")


def rand_int(lo: int, hi: int) -> int:
    return random.randint(lo, hi)


def padd(xs, n, x):
    assert len(xs) <= n
    xs.extend([x] * (n - len(xs)))
    return xs


def is_pow2(x: int) -> bool:
    return x > 0 and (x & (x - 1)) == 0


# x가 2의 거듭제곱일 때 최상위 비트의 위치
def msb_pow2(x: int) -> int:
    assert is_pow2(x), f"{x} is not a power of 2"
    return x.bit_length() - 1


# x보다 큰 2의 거듭제곱 중 최솟값
def min_pow2_gt(x: int) -> int:
    assert x >= 0
    if x == 0:
        return 1
    k = math.floor(math.log2(x)) + 1
    return 2**k


# 2**k가 x의 약수가 되는 가장 큰 k
def max_log2(x: int) -> int:
    assert x >= 0
    if x == 0:
        return 0

    k = 0
    while x % 2 == 0:
        x //= 2
        k += 1
    return k


def is_prime(x: int) -> bool:
    if x < 2:
        return False
    if x == 2:
        return True
    if x % 2 == 0:
        return False
    for i in range(3, int(x**0.5), 2):
        if x % i == 0:
            return False
    return True


def find_prime_divisors(n: int) -> list[int]:
    divisors = []
    d = 2

    # sqrt(n)까지 모든 수로 나누어떨어지는지 확인
    while d * d <= n:
        if n % d == 0:
            divisors.append(d)
            # d를 인수로 갖는 만큼 모두 나눔
            while n % d == 0:
                n //= d
        # 2 다음에는 홀수만 확인
        d += 1 if d == 2 else 2

    # n에 남은 값이 있으면 소수
    if n > 1:
        divisors.append(n)

    return divisors
