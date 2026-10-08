# 학습 노트

# 수학

- [`mulDiv` 정리](./foundry/src/MulDiv.sol)
- [타원곡선 덧셈](https://www.desmos.com/calculator/efumvebyyn)
- [ECDSA](./excalidraw/math/ecdsa.png)
- [ECDSA 논스 재사용](./excalidraw/math/ecdsa-nonce-reuse.png)
  - [코드](./python/math/ecdsa.ipynb)
- [Schnorr](./excalidraw/math/schnorr.png)
- [Schnorr 다중 서명](./excalidraw/math/schnorr-multisig.png)
- [확장 유클리드 알고리즘](./python/math/euclid.ipynb)

# DeFi

- [DCA 볼트](./foundry/src/dca/DCA.sol)
- [Aave V3 풀 2개 사이의 수익률 최적화](./python/yield-opt.ipynb)
- [볼트 인플레이션](./foundry/test/Vault.t.sol)
  - [그래프](https://www.desmos.com/calculator/orugjruk99)
  - [노트](./excalidraw/vault-inflation.png)
- [63 / 64 가스 규칙](./foundry/test/Gas.t.sol)
- [대출 금리 PID 제어기](./python/pid.ipynb)
- [볼트와 리베이스의 수학적 동등성](./excalidraw/vault-rebase.png)
  - [코드](./foundry/test/VaultAndRebase.t.sol)

# EVM

- [배열 길이 조작](./foundry/test/FalseArrLen.t.sol)

# 알고리즘

### 머클 트리

- [알고리즘](./excalidraw/algo/merkle-algo.png)
- [코드](./python/algo/merkle.ipynb)

### 증분 머클 트리

- [알고리즘](./excalidraw/algo/merkle-inc.png)
- [코드](./python/algo/merkle_inc.ipynb)
- [Solidity](./foundry/src/MerkleInc.sol)

# 고속 푸리에 변환

- [소개](./excalidraw/algo/fft/fft-intro.png)
- [정의](./excalidraw/algo/fft/fft-definitions.png)
- [알고리즘](./excalidraw/algo/fft/fft-algo.png)
- [비트 순서 뒤집기](./excalidraw/algo/fft/fft-bit-reversal.png)
- [코드](./python/algo/fft.ipynb)

# Groth16

- [R1CS](./excalidraw/groth16/r1cs.png)

# ZKStark

- [STARK 해부](https://aszepieniec.github.io/stark-anatomy/)
- [STARK 1부: 다항식으로 증명하기](https://vitalik.eth.limo/general/2017/11/09/starks_part_1.html)
- [STARK 2부: 반가운 FRI-day](https://vitalik.eth.limo/general/2017/11/22/starks_part_2.html)
- [STARK 3부: 세부 원리 살펴보기](https://vitalik.eth.limo/general/2018/07/21/starks_part_3.html)
- [STARK 101](https://starkware.co/stark-101/)
- [간단한 Zk-STARK 증명 따라가기](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4308637)
- [A41](https://encrypt.a41.io/zk/stark/fri)
- [손으로 풀어보는 STARK](https://dev.risczero.com/proof-system/stark-by-hand)
- [Dan Boneh와 함께하는 FRI와 근접성 증명 1부](https://zkhack.dev/whiteboard/s2m7/)
- [고속 Reed-Solomon IOP(FRI) 근접성 검사](https://rot256.dev/post/fri/)
- [STARK 세계의 DEEP FRI: 구체적인 예제로 배우는 고급 수학](https://blog.lambdaclass.com/diving-deep-fri/)
- [FRI 저차수 검사 실전 노트](https://hackmd.io/@deanstef/SJTT3MDhC)
- [Sin7Y 기술 리뷰 (18): 영지식 증명 알고리즘 ZK-Stark와 FRI 프로토콜](https://hackmd.io/@sin7y/r1r0IE40K)
- [Sin7Y 기술 리뷰 (25): STARK 기술 심층 분석](https://hackmd.io/@sin7y/HktwgoeKq)
- [zk-STARK의 FRI 프로토콜](https://mirror.xyz/rafal0x.eth/UUG7ivM23AYW_jbhxayWGjXzmHK6kfrB55NULD3hsbo)

### 코드

- [ethereum/research/mimic_stark](https://github.com/ethereum/research/blob/master/mimc_stark/fri.py)
- [remonyffenegger/stark-tutorial](https://github.com/remonyffenegger/stark-tutorial/blob/main/zk-stark-walkthrough.ipynb)
- [lambdaclass/lambdaworks](https://github.com/lambdaclass/lambdaworks/tree/main/crates/provers/stark)
- [risc0/risc0](https://github.com/risc0/risc0/tree/main)
- [facebook/winterfell](https://github.com/facebook/winterfell)
- [microbecode/stark-from-zero](https://github.com/microbecode/stark-from-zero)

### 동영상

- [YouTube 재생목록](https://www.youtube.com/playlist?list=PLnVBX9WZbN1YPRYprLkr3QjKSlp_0epeJ)
