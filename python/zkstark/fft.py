# 수론적 변환(NTT) - 모듈러 연산에서의 FFT


# 재귀 FFT
def fft_rec(f: list[int], ws: list[int], p: int) -> list[int]:
    """
    f = 차수가 N 미만인 다항식
    ws[i] = w^i, 여기서 w는 1의 원시 N제곱근
    p = x mod p
    [f(ws[0]), f(ws[1]), ..., f(ws[N-1])] 반환
    """
    n = len(f)
    assert n & (n - 1) == 0, f"{n} is not a power of 2"
    assert len(ws) == n, f"{len(ws)} != {n}"

    if n == 1:
        return f

    # 선택 사항 - x가 1의 원시 N제곱근인지 확인
    w = ws[1]
    assert pow(w, n, p) == 1, f"{w}^{n} mod {p} != 1"
    assert pow(w, n // 2, p) == p - 1, f"{w}^({n} / 2) mod {p} != -1"

    f_even = fft_rec(f[::2], ws[::2], p)
    f_odd = fft_rec(f[1::2], ws[::2], p)
    ys = [0] * n

    h = n // 2
    for i in range(h):
        # -1 = w^(n/2)
        # -w^i = -1 * w^i = w^(n/2 + i)
        # f(x)  = f_even(x^2) + x * f_odd(x^2)
        # f(-x) = f_even(x^2) - x * f_odd(x^2)
        ys[i] = (f_even[i] + ws[i] * f_odd[i]) % p
        ys[h + i] = (f_even[i] - ws[i] * f_odd[i]) % p

    return ys


# 재귀 없는 FFT
# N개 점(ws)에서 다항식 f의 값 계산
def fft(f: list[int], ws: list[int], p: int) -> list[int]:
    n = len(f)
    assert n & (n - 1) == 0, f"{n} is not a power of 2"
    assert len(ws) == n, f"{len(ws)} != {n}"

    ys = [0] * n

    # 짝수·홀수 항의 최종 위치를 ys에 대응시킴
    # 비트 순서 뒤집기
    # 시작 인덱스 = 최종 인덱스의 비트 순서를 뒤집은 값
    rev = 0
    for i in range(n):
        ys[i] = f[rev]
        # 왼쪽에서 오른쪽으로 올림 처리
        mask = n >> 1
        while rev & mask:
            # mask가 1인 위치를 0으로 설정
            rev &= ~mask
            # 1을 오른쪽으로 이동
            mask >>= 1
        # 올림 처리 후 해당 비트 위치에 1을 배치
        rev |= mask

    # 병합
    k = n
    s = 2
    while k > 1:
        for i in range(0, n, s):
            h = s // 2
            for j in range(i, i + h):
                f_even = ys[j]
                f_odd = ys[j + h]
                # 반복 k에서 wi = (w^j)^k = w^(j * k % n)이므로
                #      다음 반복의 wi = w^(j * (k // 2) % n)
                wi = ws[(j * (k // 2)) % n]

                ys[j] = (f_even + wi * f_odd) % p
                ys[j + h] = (f_even - wi * f_odd) % p

        s *= 2
        k //= 2

    return ys


# 역 FFT
# N개 평가값(ys)으로 차수가 N 미만인 다항식을 보간
# inverse fft = N^(-1) * fft(ys, [1, w^(-1), w^(-2), ..., w^(-(N-1))], p)
def ifft(ys: list[int], ws: list[int], p: int) -> list[int]:
    n = len(ys)
    # x = a^(-1) mod P
    # x * a^(-1) = 1 mod P
    # 페르마의 소정리
    # a^(P - 1) = 1 mod P이므로 a^(P - 2) = a^(-1)
    n_inv = pow(n, p - 2, p)
    # w^(-i) = w^(N - i)
    ws_inv = [0] * n
    ws_inv[0] = ws[0]
    for i in range(1, n):
        ws_inv[i] = ws[n - i]

    return [(n_inv * c) % p for c in fft(ys, ws_inv, p)]


# FFT 출력을 확인하기 위해 xs에서 다항식의 값 계산
def eval_poly(f: list[int], xs: list[int], p: int) -> list[int]:
    ys = [0] * len(xs)
    for i, xi in enumerate(xs):
        x = 1
        y = 0
        for c in f:
            y += c * x
            x *= xi
        y %= p
        ys[i] = y

    return ys
