import math

Q96 = 2**96
MIN_DY_DELTA = 0.001


# 틱을 제곱근 가격 x 96으로 변환
def tick_to_sqrt_p_96(tick):
    return int(1.0001 ** (tick / 2) * Q96)


def tick_to_sqrt_p(tick):
    return 1.0001 ** (tick / 2)


def tick_to_p(tick):
    return 1.0001**tick


def sqrt_p_to_tick(sqrt_price):
    return int(round(2 * math.log(sqrt_price) / math.log(1.0001)))


def round_tick(tick, tick_spacing):
    return int(round(tick / tick_spacing) * tick_spacing)


def calc_x(L, s):
    assert s >= 0, f"{s}"
    if s == 0:
        return math.inf
    return L / s


def calc_y(L, s):
    assert s >= 0, f"{s}"
    return L * s


def calc_dx(L, s_lo, s_hi):
    assert s_lo >= 0, f"{s_lo}"
    assert s_hi >= 0, f"{s_hi}"
    if s_lo >= s_hi:
        return 0
    if s_lo == 0:
        return math.inf
    # 1 / math.inf = 0
    return L * (1 / s_lo - 1 / s_hi)


def calc_dy(L, s_lo, s_hi):
    assert s_lo >= 0, f"{s_lo}"
    assert s_hi >= 0, f"{s_hi}"
    if s_lo >= s_hi:
        return 0
    return L * (s_hi - s_lo)


# dx = L(1/s_lo - 1/s_hi)
# dy = L(s_hi - s_lo)
def calc_dx_to_s_lo(L, s_hi, dx):
    assert s_hi > 0, f"{s_hi}"
    assert dx >= 0, f"{dx}"
    return 1 / (dx / L + 1 / s_hi)


def calc_dx_to_s_hi(L, s_lo, dx):
    assert s_lo > 0, f"{s_lo}"
    assert dx >= 0, f"{dx}"
    return 1 / (-dx / L + 1 / s_lo)


def calc_dy_to_s_lo(L, s_hi, dy):
    assert s_hi > 0, f"{s_hi}"
    assert dy >= 0, f"{dy}"
    return -dy / L + s_hi


def calc_dy_to_s_hi(L, s_lo, dy):
    assert s_lo > 0, f"{s_lo}"
    assert dy >= 0, f"{dy}"
    return dy / L + s_lo


# 다음 단계
def nxt(pool, i, up):
    if i + 1 >= len(pool):
        if up:
            return (math.inf, math.inf, 0)
        else:
            return (0, 0, 0)
    return pool[i + 1]


def calc_amt_out(i, o, di, f):
    di *= 1 - f
    return o * di / (i + di)


# 풀 A에 넣을 최적의 dy 수량(수수료 포함, dya -> dx -> dyb)
def calc_opt_dy_in(xa, ya, xb, yb, fa, fb):
    k0 = xa * ya * xb * yb * (1 - fa) * (1 - fb)
    k1 = (xb + xa * (1 - fb)) * (1 - fa)
    a = k1 * k1
    b = 2 * k1 * xb * ya
    c = (xb * ya) ** 2 - k0
    return (-b + math.sqrt(b * b - 4 * a * c)) / (2 * a)


def calc_opt_dya(la, sa, lb, sb, fa, fb):
    assert 0 <= sa < sb, f"sa: {sa}, sb: {sb}"
    xa = calc_x(la, sa)
    ya = calc_y(la, sa)
    xb = calc_x(lb, sb)
    yb = calc_y(lb, sb)

    # print(f"la: {la}, sa: {sa}, lb: {lb}, sb: {sb}, fa: {fa}, fb: {fb}")
    # print(f"xa: {xa}, ya: {ya}, xb: {xb}, yb: {yb}")

    dya = calc_opt_dy_in(xa, ya, xb, yb, fa, fb)
    if dya <= 0:
        return (0, 0, sa, sb)

    dx = calc_amt_out(ya, xa, dya, fa)
    dyb = calc_amt_out(xb, yb, dx, fb)
    # 작은 반올림 오차가 있으면 종료
    if abs(dya - dyb) < MIN_DY_DELTA:
        return (0, 0, sa, sb)

    assert dya <= dyb, f"{dya} > {dyb}"
    # 스왑 후 sa와 sb 확인
    sa_swap = calc_dy_to_s_hi(la, sa, dya * (1 - fa))
    sb_swap = calc_dx_to_s_lo(lb, sb, dx * (1 - fb))
    assert (
        sa <= sa_swap <= sb_swap <= sb
    ), f"sa: {sa}, sa_swap: {sa_swap}, sb_swap: {sb_swap}, sb: {sb}"
    return (dya, dyb, sa_swap, sb_swap)


def swap_to_sa_hi(xa, xb, la, sa, sa_lo, sa_hi, lb, sb, sb_lo, sb_hi, fa, fb):
    dya = calc_dy(la, sa_lo, sa_hi) / (1 - fa)
    sa = sa_hi
    sb = calc_dx_to_s_lo(lb, sb_hi, xa * (1 - fb))
    assert sb_lo <= sb, f"{sb_lo} > {sb}"
    dyb = calc_dy(lb, sb, sb_hi)
    return (dya, dyb, sa, sb)


def swap_to_sb_lo(xa, xb, la, sa, sa_lo, sa_hi, lb, sb, sb_lo, sb_hi, fa, fb):
    dx = min(xa, xb / (1 - fb))
    if dx == xa:
        sa = sa_hi
    else:
        sa = calc_dx_to_s_hi(la, sa_lo, dx)
        assert sa <= sa_hi, f"{sa} > {sa_hi}"
    dya = calc_dy(la, sa_lo, sa) / (1 - fa)
    if dx == xa:
        sb = calc_dx_to_s_lo(lb, sb_hi, xa * (1 - fb))
        assert sb_lo <= sb, f"{sb_lo} > {sb}"
    else:
        sb = sb_lo
    dyb = calc_dy(lb, sb, sb_hi)
    return (dya, dyb, sa, sb)


# pa < pb
# dya -> dx -> dyb
# pool = [(제곱근 가격 하한, 제곱근 가격 상한, 유동성)]
def calc_dya(pool_a, pool_b, fa, fb):
    (sa_lo, sa_hi, la) = pool_a[0]
    (sb_lo, sb_hi, lb) = pool_b[0]
    a = 0
    b = 0
    dya = 0
    dyb = 0
    sa = sa_lo
    sb = sb_hi

    while sa_lo < sb_hi:
        xa = calc_dx(la, sa_lo, sa_hi)
        xb = calc_dx(lb, sb_lo, sb_hi)
        if sa_hi <= sb_lo:
            if xa <= xb:
                # sa_hi까지 스왑
                # print("opt", sa, sb)
                (da, db, sa, sb) = swap_to_sa_hi(
                    xa, xb, la, sa, sa_lo, sa_hi, lb, sb, sb_lo, sb_hi, fa, fb
                )
                dya += da
                dyb += db
            else:
                # sb_lo까지 스왑
                (da, db, sa, sb) = swap_to_sb_lo(
                    xa, xb, la, sa, sa_lo, sa_hi, lb, sb, sb_lo, sb_hi, fa, fb
                )
                dya += da
                dyb += db
        else:
            (dya_opt, dyb_opt, sa_swap, sb_swap) = calc_opt_dya(la, sa, lb, sb, fa, fb)
            if dya_opt == 0:
                break
            if sa_hi < sa_swap:
                # sa_hi까지 스왑
                (da, db, sa, sb) = swap_to_sa_hi(
                    xa, xb, la, sa, sa_lo, sa_hi, lb, sb, sb_lo, sb_hi, fa, fb
                )
                dya += da
                dyb += db
            elif sb_swap < sb_lo:
                # sb_lo까지 스왑
                (da, db, sa, sb) = swap_to_sb_lo(
                    xa, xb, la, sa, sa_lo, sa_hi, lb, sb, sb_lo, sb_hi, fa, fb
                )
                dya += da
                dyb += db
            else:
                # 최적 가격(sa_swap과 sb_swap 사이)까지 스왑
                dya += dya_opt
                dyb += dyb_opt
                sa_lo = sa_swap
                sb_hi = sb_swap
                sa = sa_swap
                sb = sb_swap
                break
        assert sa <= sb, f"{sa} > {sb}"
        # 가격 갱신
        if sa == sa_hi:
            (sa_lo, sa_hi, la) = nxt(pool_a, a, True)
            a += 1
        else:
            assert sa_lo <= sa, f"{sa_lo} > {sa}"
            sa_lo = sa
        if sb == sb_lo:
            (sb_lo, sb_hi, lb) = nxt(pool_b, b, False)
            b += 1
        else:
            assert sb <= sb_hi, f"{sb} > {sb_hi}"
            sb_hi = sb

    assert dya <= dyb, f"{dya} > {dyb}"
    assert sa <= sb, f"{sa} > {sb}"
    return (dya, dyb, sa, sb)
