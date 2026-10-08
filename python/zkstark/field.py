from __future__ import annotations
from utils import find_prime_divisors


# 확장 유클리드 알고리즘으로 곱셈 역원 계산
# TODO: 이게 뭐지?
def xgcd(x: int, y: int) -> (int, int, int):
    old_r, r = (x, y)
    old_s, s = (1, 0)
    old_t, t = (0, 1)

    while r != 0:
        quotient = old_r // r
        old_r, r = (r, old_r - quotient * r)
        old_s, s = (s, old_s - quotient * s)
        old_t, t = (t, old_t - quotient * t)

    return old_s, old_t, old_r  # a, b, g


# 체의 원소
class F:
    def __init__(self, v: int, p: int):
        self.v = v % p
        self.p = p

    def wrap(self, v: int) -> F:
        return F(v, self.p)

    def unwrap(self) -> int:
        return self.v

    def check(self, x: int | F) -> F:
        if isinstance(x, int):
            return self.wrap(x)
        assert self.p == x.p
        return x

    def inv(self) -> F:
        # p가 소수이면 페르마의 소정리 사용
        # a^(p - 1) = a * a^(p - 2) = 1 mod p
        # return self.wrap(pow(a, p - 2, p))
        a, _, _ = xgcd(self.v, self.p)
        return self.wrap(a)

    # F + (int | F)
    def __add__(self, x: int | F) -> F:
        x = self.check(x)
        return self.wrap((self.v + x.v) % self.p)

    # (int | F) + F
    def __radd__(self, x: int | F) -> F:
        # 덧셈은 교환법칙을 만족함
        return self.__add__(x)

    # F - (int | F)
    def __sub__(self, x: int | F) -> F:
        x = self.check(x)
        return self.wrap((self.v - x.v) % self.p)

    # (int | F) - F
    def __rsub__(self, x: int | F) -> F:
        x = self.check(x)
        return x.__sub__(self)

    # F * (int | F)
    def __mul__(self, x: int | F) -> F:
        x = self.check(x)
        return self.wrap((self.v * x.v) % self.p)

    # (int | F) * F
    def __rmul__(self, x: int | F) -> F:
        # 곱셈은 교환법칙을 만족함
        return self.__mul__(x)

    # F / (int | F)
    def __truediv__(self, x: int | F) -> F:
        x = self.check(x)
        assert x.v != 0, "div by 0"
        return self * x.inv()

    # (int | F) / F
    def __rtruediv__(self, x) -> F:
        x = self.check(x)
        return x.__truediv__(self)

    # F**int
    def __pow__(self, exp: int) -> F:
        if exp == 0:
            return self.wrap(1)

        if exp < 0:
            return self.inv() ** (-exp)

        return self.wrap(pow(self.v, exp, self.p))

    def __eq__(self, x: int | F) -> bool:
        x = self.check(x)
        return (self.v % self.p) == (x.v % self.p)

    def __neq__(self, x: int | F) -> bool:
        x = self.check(x)
        return (self.v % self.p) != (x.v % self.p)

    def __neg__(self) -> F:
        return self.wrap((self.p - self.v) % self.p)

    def __str__(self):
        return str(self.v)

    def __repr__(self):
        return str(self.v)

    # 집합의 키로 사용
    def __hash__(self):
        return hash((self.v, self.p))


def find_generator(p: int) -> int | None:
    # 생성원 g는 mod P 유한체 F[P]의 원소로, 다음을 만족함
    # {g^0, g^1, ..., g^(P-1)} = {1, 2, 3, ..., P - 1}

    # g를 빠르게 찾는 방법
    # P가 소수일 때 g가 F[P]의 생성원일 필요충분조건은
    # g^((P-1) / q) != 1 mod P
    # P - 1의 모든 소인수 q에 대해 위 식이 성립하는 것

    prime_divs = find_prime_divisors(p - 1)
    for x in range(1, p):
        if all(pow(x, (p - 1) // q, p) != 1 for q in prime_divs):
            return x
    return None


def generate(g: int, n: int, p: int) -> list[int]:
    """
    g = F[P, *]의 생성원
    n = 생성할 부분군 G의 위수
    p = 소수 P
    """
    assert n <= p

    G = [0] * n
    G[0] = 1
    for i in range(1, n):
        G[i] = (G[i - 1] * g) % p
        assert G[i] != 1, f"g^{i} = 1"

    # g^n = 1인지 확인
    assert (G[-1] * g) % p == 1, f"g^{n} = {(G[-1] * g) % p}"
    assert len(set(G)) == n

    return G


# 1의 원시 N제곱근
def get_primitive_root(g: int, n: int, p: int) -> int:
    """
    g = F[P, *]의 생성원
    n = 1의 원시 n제곱근
    p = 소수 P
    """
    # F[P, *] = F[P]의 곱셈 부분군 = {1, 2, 3, ..., P - 1}
    # g = F[P, *]의 생성원
    # |F[P, *]| = P - 1
    # k가 P - 1의 약수이면 g^k는 크기가 (P - 1) / k인 군을 생성함
    # (P - 1) / k = n -> k = (P - 1) / n
    k = (p - 1) // n
    return pow(g, k, p)
