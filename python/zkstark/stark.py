from __future__ import annotations
from polynomial import Polynomial, X
from field import F
import field
import fft_poly
import fri
import merkle
from iop import Channel, Msg, IStarkProver, IStarkVerifier
from utils import is_prime, is_pow2, min_pow2_gt, rand_int


class Prover(IStarkProver):
    def __init__(self, **kwargs):
        # 소수
        P: int = kwargs["P"]
        # 소체 P의 곱셈 부분군 F[P, *]의 생성원
        g: int = kwargs["g"]

        # TODO: 여기서 trace_domain을 만들까?
        # 트레이스 다항식
        t: Polynomial = kwargs["trace_poly"]
        # 트레이스 평가 영역
        trace_domain: list[int] = kwargs["trace_domain"]
        trace_len = len(trace_domain)
        assert is_pow2(trace_len)
        assert t.degree() < trace_len

        # 확장 계수, exp_factor * trace_len = N = eval_domain의 크기
        exp_factor: int = kwargs["exp_factor"]
        assert is_pow2(exp_factor)
        N = exp_factor * trace_len
        assert N < P

        # 1의 원시 N제곱근
        w: int = field.get_primitive_root(g, N, P)
        assert pow(w, N, P) == 1
        assert pow(w, N // 2, P) == (-1 % P)
        # 1의 N제곱근
        roots: list[int] = field.generate(w, N, P)
        assert len(roots) == N

        # trace_domain과 eval_domain이 서로 겹치지 않도록
        # FRI와 STARK의 평가 영역을 g만큼 이동
        eval_domain = [(g * wi) % P for wi in roots]
        assert (
            intersec := set(eval_domain) & set(trace_domain)
        ) == set(), f"eval domains not disjoint {intersec}"

        # T = trace_domain으로 두고
        #     L = 1의 N제곱근으로 둠
        # T와 L은 F[P, *]의 부분군 -> |T|와 |L|은 |F[P, *]| = P - 1의 약수
        assert (P - 1) % trace_len == 0
        assert (P - 1) % N == 0

        # 제약 다항식 c(t(x))
        c: Polynomial = kwargs["constraint_poly"]
        # 제약 다항식의 평가 영역 크기
        c_size = min_pow2_gt(c.degree())
        assert trace_len <= c_size <= N
        assert (P - 1) % c_size == 0
        # 제약 다항식의 평가 영역
        c_eval_domain = field.generate(
            field.get_primitive_root(g, c_size, P), c_size, P
        )

        # z(x) = (x - g^0)(x - g^1)...(x - g^(T-1)) = x^T - 1, 여기서 T = trace_len
        z: Polynomial = X(trace_len, lambda x: F(x, P)) - 1

        # 몫 다항식 q(x) = c(t(x)) / z(x)
        q = fft_poly.div(c, z, c_eval_domain, P, g)
        max_degree = q.degree()
        assert max_degree < trace_len

        self.P: int = P
        self.g: int = g
        self.eval_domain: list[int] = eval_domain
        # eval_domain에서 FFT를 사용하기 위해 필요
        self.roots: list[int] = roots
        self.trace_len: int = trace_len

        self.t: Polynomial = t
        self.c: Polynomial = c
        self.z: Polynomial = z
        self.q: Polynomial = q
        # 몫 다항식 q(x)의 최대 차수
        self.max_degree: int = max_degree
        self.q_adj: Polynomial | None = None

        self.t_hashes: list[str] = []
        self.q_hashes: list[str] = []
        self.t_merkle_root: str | None = None
        self.q_merkle_root: str | None = None

        self.fri_prover: fri.Prover = fri.Prover(
            P=P,
            exp_factor=exp_factor,
            eval_domain=eval_domain,
        )

    def fri(self) -> fri.Prover:
        return self.fri_prover

    def commit(self, chan: Channel):
        assert self.t_merkle_root is None
        assert self.q_merkle_root is None
        assert self.q_adj is None

        # 차수 조정
        # 제약 다항식 C[j] 전체의 최대 차수를 max_degree로 둠
        # D > max_degree를 만족하는 가장 작은 k에 대해 D = 2**k로 둠
        # C[j]의 차수를 D - 1로 조정
        # C[j]의 차수가 D[j]일 때
        # 차수를 조정한 다항식 = C[j](x) * (A[j] * x^(D - D[j] - 1) + B[j])
        # 여기서 A[j]와 B[j]는 검증자가 제공한 무작위 값
        deg_adj = min_pow2_gt(self.max_degree)
        assert deg_adj > self.max_degree

        (a, b) = chan.send(
            dst="verifier", msg=Msg(msg_type="stark_degree_adj", data=self.max_degree)
        )
        adj = a * X(deg_adj - self.max_degree - 1, lambda x: F(x, self.P)) + b
        q_adj = self.q * adj
        assert is_pow2(q_adj.degree() + 1)
        assert q_adj.degree() == self.trace_len - 1

        self.q_adj = q_adj

        # t(L)
        tx = fft_poly.eval(self.t, self.roots, self.P, self.g)
        # q_adj(L)
        qx = fft_poly.eval(self.q_adj, self.roots, self.P, self.g)
        self.t_hashes = [merkle.hash_leaf(str(y)) for y in tx]
        self.q_hashes = [merkle.hash_leaf(str(y)) for y in qx]
        self.t_merkle_root = merkle.commit(self.t_hashes)
        self.q_merkle_root = merkle.commit(self.q_hashes)

        chan.send(
            dst="verifier",
            msg=Msg(
                msg_type="stark_merkle_roots",
                data=(self.t_merkle_root, self.q_merkle_root),
            ),
        )

        self.fri_prover.commit(qx, chan)

        assert self.q_merkle_root == self.fri_prover.merkle_roots[0]

    def prove(self, idx: int, chan: Channel):
        x = self.eval_domain[idx]
        tx = self.t(x)
        qx = self.q_adj(x)
        t_proof = merkle.open(self.t_hashes, idx)
        q_proof = merkle.open(self.q_hashes, idx)

        chan.send(
            dst="verifier",
            msg=Msg(msg_type="stark_proofs", data=(tx, qx, t_proof, q_proof)),
        )


class Verifier(IStarkVerifier):
    def __init__(self, **kwargs):
        # 소수
        P: int = kwargs["P"]
        # 소체 P의 곱셈 부분군 F[P, *]의 생성원
        g: int = kwargs["g"]

        # 트레이스 평가 영역
        trace_len: int = kwargs["trace_len"]
        assert is_pow2(trace_len)

        # 확장 계수, exp_factor * trace_len = N = eval_domain의 크기
        exp_factor: int = kwargs["exp_factor"]
        assert is_pow2(exp_factor)
        N = exp_factor * trace_len
        assert N < P

        # 1의 원시 N제곱근
        w: int = field.get_primitive_root(g, N, P)
        assert pow(w, N, P) == 1
        assert pow(w, N // 2, P) == (-1 % P)
        # 1의 N제곱근
        roots: list[int] = field.generate(w, N, P)
        assert len(roots) == N

        # trace_domain과 eval_domain이 서로 겹치지 않도록
        # FRI와 STARK의 평가 영역을 g만큼 이동
        eval_domain = [(g * wi) % P for wi in roots]

        # T = trace_domain으로 두고
        #     L = 1의 N제곱근으로 둠
        # T와 L은 F[P, *]의 부분군 -> |T|와 |L|은 |F[P, *]| = P - 1의 약수
        assert (P - 1) % trace_len == 0
        assert (P - 1) % N == 0

        # 값 y = t(x)에 대한 제약 다항식으로, c(y)는 0이어야 함
        c: Polynomial = kwargs["constraint_poly"]

        # z(x) = (x - g^0)(x - g^1)...(x - g^(T-1)) = x^T - 1, 여기서 T = trace_len
        z: Polynomial = X(trace_len, lambda x: F(x, P)) - 1

        self.P: int = P
        self.eval_domain: list[int] = eval_domain
        self.trace_len: int = trace_len

        self.c: Polynomial = c
        self.z: Polynomial = z
        # 몫 다항식 q(x) = c(x) / z(x)의 최대 차수
        self.max_degree: int = 0
        self.adj: Polynomial | None = None
        # 몫 다항식 q(x)의 차수를 조정하도록 증명자에게 보내는 무작위 챌린지
        self.challenges: (int, int) | None = None

        self.t_merkle_root: str | None = None
        self.q_merkle_root: str | None = None

        self.fri_verifier: fri.Verifier = fri.Verifier(
            P=P,
            w=w,
            shift=g,
            exp_factor=exp_factor,
            eval_domain=eval_domain,
        )

    def fri(self) -> fri.Verifier:
        return self.fri_verifier

    def set_adj(self, max_degree: int, chan: Channel):
        assert self.challenges is None
        assert self.adj is None

        assert max_degree < self.trace_len
        self.max_degree = max_degree

        a = rand_int(1, self.P - 1)
        b = rand_int(1, self.P - 1)
        self.challenges = (a, b)

        # q(x)의 최대 차수
        deg_adj = min_pow2_gt(max_degree)
        assert deg_adj > max_degree

        (a, b) = self.challenges
        self.adj = a * X(deg_adj - max_degree - 1, lambda x: F(x, self.P)) + b

        chan.send(dst="prover", msg=Msg(msg_type="stark_degree_adj", data=(a, b)))

    def set_merkle_roots(self, merkle_roots: (str, str)):
        (t_merkle_root, q_merkle_root) = merkle_roots
        assert self.t_merkle_root is None
        assert self.q_merkle_root is None
        self.t_merkle_root = t_merkle_root
        self.q_merkle_root = q_merkle_root

    # 쿼리 전 사전 검사
    def check(self):
        assert self.q_merkle_root == self.fri_verifier.merkle_roots[0]

    def query(self, idx: int, chan: Channel):
        (tx, qx, t_proof, q_proof) = chan.send(
            dst="prover", msg=Msg(msg_type="stark_prove", data=idx)
        )
        self.verify(idx, tx, qx, t_proof, q_proof)

    def verify(self, idx: int, tx: F, qx: F, t_proof: list[str], q_proof: list[str]):
        x = self.eval_domain[idx]
        cx = self.c(tx)
        zx = self.z(x)
        adjx = self.adj(x)
        assert qx * zx == cx * adjx

        assert merkle.verify(
            t_proof, self.t_merkle_root, merkle.hash_leaf(str(tx)), idx
        )
        assert merkle.verify(
            q_proof, self.q_merkle_root, merkle.hash_leaf(str(qx)), idx
        )
