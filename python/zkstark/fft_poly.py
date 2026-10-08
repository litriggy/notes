from field import F
from polynomial import Polynomial
from fft import fft, ifft
from utils import padd


# FFT로 다항식의 값 계산
def eval(f: Polynomial, ws: list[int], p: int, shift: int = 1) -> list[F]:
    """
    ws = 1의 N제곱근
    p = 소수
    """
    # 평가 영역 = [shift * w for w in ws]
    # q(x) = f(ax)로 정의
    #        q(w^i) = f(aw^i)
    q = f.scale(shift)
    cs = [c.unwrap() for c in q.cs]
    # 평가 영역이 다항식의 차수보다 크므로 0으로 채움
    cs = padd(cs, len(ws), 0)
    ys = fft(cs, ws, p)
    return [F(y, p) for y in ys]


# 역 FFT로 다항식 보간
def interp(ys: list[int | F], ws: list[int], p: int, shift: int = 1) -> Polynomial:
    # 평가 영역 = [shift * w for w in ws]
    # q(x) = f(ax)로 정의
    #        q(w^i) = f(aw^i)
    #        q(x/a) = f(x)
    ys = [y if isinstance(y, int) else y.unwrap() for y in ys]
    cs = ifft(ys, ws, p)
    q = Polynomial(cs, lambda x: F(x, p))
    s_inv = F(shift, p).inv()
    return q.scale(s_inv)


# 다항식 q = c / z 계산
def div(
    c: Polynomial, z: Polynomial, ws: list[int], p: int, shift: int = 1
) -> Polynomial:
    """
    ws의 모든 w에 대해 z(w) = 0이고, 모든 x = shift * w에 대해 z(x) != 0
    """
    assert c.degree() >= z.degree()
    cx = eval(c, ws, p, shift)
    zx = eval(z, ws, p, shift)
    assert all(y != 0 for y in zx)
    return interp([ci / zi for (ci, zi) in zip(cx, zx)], ws, p, shift)
