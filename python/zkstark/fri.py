from __future__ import annotations
import merkle
from field import F
import field
from polynomial import Polynomial
import polynomial
import fft_poly
from iop import Channel, Msg, IFriProver, IFriVerifier
from utils import is_pow2, fiat_shamir


class Prover(IFriProver):
    def __init__(self, **kwargs):
        # 소수
        P: int = kwargs["P"]
        # 트레이스 길이 T에서 RS 코드 길이 N으로 늘리는 확장 계수
        # exp_factor * T = N
        exp_factor: int = kwargs["exp_factor"]
        # FRI 평가 영역, 보통 L로 표기
        eval_domain: list[int] = kwargs["eval_domain"]

        # 초기 영역 크기
        N = len(eval_domain)

        assert N < P, f"{N} >= {P}"
        assert is_pow2(N), f"N = {N} is not a power of 2"
        assert 2 <= exp_factor, f"exp factor = {exp_factor} < 2"
        # N = exp_factor * T가 2의 거듭제곱이므로 exp_factor도 2의 거듭제곱이어야 함
        assert is_pow2(exp_factor), f"exp_factor = {exp_factor} is a power of 2"

        self.P: int = P
        self.N: int = N
        self.exp_factor = exp_factor
        self.eval_domain: list[int] = eval_domain
        self.hashes: list[list[str]] = []
        self.merkle_roots: list[str] = []
        self.challenges: list[F] = []
        self.codewords: list[list[F]] = []
        # x를 F로 감싸는 함수
        self.wrap = lambda x: F(x, P)

    def commit(self, codeword: list[F], chan: Channel):
        """
        0. f[0] = f
           L^(2^0) = L
           L^(2^(i+1)) = [x^2 for x in L^(2^i)]
        1. L^(2^i)에서 다항식 f[i]의 값 계산
        2. f[i](L^(2^i))로 Merkle 트리 생성
        3. 증명자가 검증자에게 Merkle 루트 전송
        4. 검증자가 챌린지 B[i] 전송
        5. 증명자가 폴딩한 다항식 계산
           5.1 분리: f[i](x) = f[i, even](x^2) + x * f[i, odd](x^2)
           5.2 폴딩: f[i + 1](x) = f[i, even](x) + B[i] * f[i, odd](x)
        6. 다항식 f[i]의 차수가 0이 될 때까지 1~5 반복
        7. 마지막 폴딩의 코드워드 전송
        """
        assert len(self.merkle_roots) == 0
        assert len(self.codewords) == 0
        assert len(codeword) == self.N

        # 영역 크기
        n = self.N
        # 평가 영역
        Li = self.eval_domain
        # t = 트레이스 길이 -> 다항식 차수 < t
        # n = t * exp_factor
        # t = 1일 때 -> n = exp_factor -> 다항식 차수 = 0
        while n >= self.exp_factor:
            # Reed Solomon 코드
            self.codewords.append(codeword)

            # 다음 반복
            n //= 2
            if n >= self.exp_factor:
                # Merkle 루트 커밋
                hs = [merkle.hash_leaf(str(c)) for c in codeword]
                merkle_root = merkle.commit(hs)
                self.hashes.append(hs)
                self.merkle_roots.append(merkle_root)
                chan.send(
                    dst="verifier",
                    msg=Msg(msg_type="fri_merkle_root", data=merkle_root),
                )

                # 무작위 챌린지 받기
                c = chan.send(dst="verifier", msg=Msg(msg_type="fri_challenge"))
                self.challenges.append(self.wrap(c))
                # 폴딩
                # f_even(x^2) = (f(x) + f(-x)) / 2
                # f_odd(x^2) = (f(x) - f(-x)) / 2x
                # f_fold(x^2) = f_even(x^2) + c * f_odd(x^2)
                # f_fold(x^2)의 평가값
                vals = []
                assert len(Li) == 2 * n
                for i in range(n):
                    x = Li[i]
                    f_plus = codeword[i]
                    f_minus = codeword[n + i]
                    f_even = (f_plus + f_minus) / 2
                    f_odd = (f_plus - f_minus) / (2 * x)
                    f_fold = f_even + c * f_odd
                    vals.append(f_fold)
                codeword = vals

                # L^(2^(i+1)) = [x^2 for x in L^(2^i)]
                Li = [x * x for x in Li[:n]]
            else:
                chan.send(
                    dst="verifier",
                    msg=Msg(msg_type="fri_last_codeword", data=codeword),
                )

    def prove(self, idx: int, chan: Channel):
        """
        0. f[0] = f
        1. 검증자가 증명자에게 무작위 챌린지 x 전송
        2. 증명자가 f[i](x), f[i](-x)와 Merkle 증명 전송
        3. 검증자가 f[i](x)와 f[i](-x)의 Merkle 증명 확인
        4. 검증자가 f[i](x)와 f[i](-x)로 f[i+1](x^2) 계산
           f[i](x)  = f[i, even](x^2) + x * f[i, odd](x^2)
           f[i](-x) = f[i, even](x^2) - x * f[i, odd](x^2)
           f[i+1](x^2) = f[i, even](x^2) + Bi * f[i, odd](x^2)
                       = (f[i](x) + f[i](-x)) / 2 + B[i] * (f[i](x) - f[i](-x)) / 2x
           검증자가 다음 단계에서 받은 f[i+1](x^2)가 위 계산과 일치하는지 확인
        5. x 갱신
           x = x*x
        6. 다항식 f[i]의 차수가 0보다 큰 동안 2~5 반복
        7. f[i]의 차수가 0이면
           -  검증자가 코드워드 f[i](Li)를 직접 확인
        """
        i = 0
        n = self.N
        # (f[i](x^(2^i)), f[i](-x^(2^i))) 목록
        vals: list[(F, F)] = []
        # (f[i](x^(2^i)), f[i](-x^(2^i)))의 Merkle 증명
        proofs: list[(list[str], list[str])] = []

        while n > self.exp_factor:
            assert idx < n, f"index {idx} > {n}"
            # f[i](x)와 f[i](-x)
            codeword = self.codewords[i]
            idx_plus = idx
            idx_minus = (n // 2 + idx) % n
            f_plus = codeword[idx_plus]
            f_minus = codeword[idx_minus]
            vals.append((f_plus, f_minus))

            # Merkle 증명
            hs = self.hashes[i]
            proof_plus = merkle.open(hs, idx_plus)
            proof_minus = merkle.open(hs, idx_minus)
            proofs.append((proof_plus, proof_minus))

            # 다음 반복
            n //= 2
            i += 1
            if n > self.exp_factor:
                # x^i -> x^(2i % N)
                # n = 8, [x^0, x^1, x^2, x^3, x^4, x^5, x^6, x^7]
                # n = 4, [x^0, x^2, x^4, x^6]
                # n = 2, [x^0, x^4]
                # 다음 반복에서 위쪽 절반을 아래쪽 절반으로 대응시킴 -> 인덱스 i를 i % (n / 2)로 변환
                idx %= n

        chan.send(
            dst="verifier",
            msg=Msg(msg_type="fri_proofs", data=(vals, proofs)),
        )


class Verifier(IFriVerifier):
    def __init__(self, **kwargs):
        # 소수
        P = kwargs["P"]
        # 1의 원시 N제곱근
        w = kwargs["w"]
        # 평가 영역을 이동하는 값(보통 F[P]의 생성원)
        shift = kwargs["shift"]
        # 트레이스 길이 T에서 RS 코드 길이 N으로 늘리는 확장 계수
        # exp_factor * T = N
        exp_factor = kwargs["exp_factor"]
        # FRI 평가 영역, 보통 L로 표기
        eval_domain: list[int] = kwargs["eval_domain"]

        # 초기 영역 크기
        N = len(eval_domain)

        assert N < P, f"{N} >= {P}"
        assert is_pow2(N), f"{N} is not a power of 2"
        assert 2 <= exp_factor, f"exp factor = {exp_factor} < 2"
        # N = exp_factor * T가 2의 거듭제곱이므로 exp_factor도 2의 거듭제곱이어야 함
        assert is_pow2(exp_factor), f"exp_factor = {exp_factor} is a power of 2"
        assert 1 <= w <= P - 1
        assert 1 <= shift <= P - 1

        self.P: int = P
        self.N: int = N
        self.w: int = w
        self.shift: int = shift
        self.exp_factor = exp_factor
        self.eval_domain: list[int] = eval_domain
        self.merkle_roots: list[str] = []
        self.challenges: list[F] = []
        self.last_codeword: list[F] = []
        # x를 F로 감싸는 함수
        self.wrap = lambda x: F(x, P)

    def push_merkle_root(self, val: str):
        self.merkle_roots.append(val)

    def set_last_codeword(self, codeword: list[F]):
        # 마지막 코드워드 길이 확인
        # 트레이스 길이 t -> 다항식 차수 < t
        # RS 코드 길이 = n = t * exp_factor (여기서는 다항식 차수 = 0이므로 t = 1)
        assert len(codeword) == self.exp_factor
        assert len(self.last_codeword) == 0
        self.last_codeword = codeword

    def get_challenge(self, chan: Channel):
        c = fiat_shamir(str(self.merkle_roots))
        self.challenges.append(self.wrap(c))
        chan.send(dst="prover", msg=Msg(msg_type="fri_challenge", data=c))

    def query(self, idx: int, chan: Channel):
        (vals, proofs) = chan.send(
            dst="prover", msg=Msg(msg_type="fri_prove", data=idx)
        )
        self.verify(idx, vals, proofs)

    def verify(
        self,
        # L에서 x의 인덱스
        idx: int,
        # (f[i](x), f[i](-x)) 목록
        vals: list[(F, F)],
        # (f[i](x), f[i](-x))의 Merkle 증명
        proofs: list[(list[str], list[str])],
    ):
        """
        Prover.prove의 주석 참고
        """
        assert len(self.merkle_roots) == len(self.challenges)
        assert len(vals) == len(proofs) == len(self.merkle_roots)
        assert idx < self.N

        i = 0
        n = self.N
        x = self.eval_domain[idx]
        fold = None

        while n > self.exp_factor:
            merkle_root = self.merkle_roots[i]
            # f[i](x)와 f[i](-x)
            (f_plus, f_minus) = vals[i]
            # f[i](x)와 f[i](-x)의 증명
            (proof_plus, proof_minus) = proofs[i]
            (idx_plus, idx_minus) = (idx, (n // 2 + idx) % n)

            # f[i](x)와 f[i](-x)의 Merkle 증명 확인
            for f, p, j in zip(
                [f_plus, f_minus], [proof_plus, proof_minus], [idx_plus, idx_minus]
            ):
                assert merkle.verify(p, merkle_root, merkle.hash_leaf(str(f)), j)

            # 폴딩 확인
            if i > 0:
                assert fold == f_plus, "fold != f[i+1](x^2)"

            # 다음 반복 또는 while 루프 이후 최종 검사를 위한 폴딩 계산
            c = self.challenges[i]
            fold = (f_plus + f_minus) / 2 + c * (f_plus - f_minus) / (2 * x)

            # 다음 반복
            n //= 2
            i += 1
            x *= x
            idx %= n

        # 마지막 폴딩 확인
        assert fold == self.last_codeword[idx]

        # 다항식을 보간하고 차수가 0인지 확인
        # (shift * w^i)^k = shift^k * w^(i*k)
        p = fft_poly.interp(
            self.last_codeword,
            field.generate(
                pow(self.w, 2 ** i, self.P),
                len(self.last_codeword),
                self.P,
            ),
            self.P,
            pow(self.shift, 2 ** i, self.P),
        )
        assert (
            p.degree() == 0
        ), f"interpolated polynomial degree = {p.degree()} > 0"
        assert (
            p(self.last_codeword) == self.last_codeword
        ), f"polynomial evaluation {p(self.last_codeword)} != {self.last_codeword}"
