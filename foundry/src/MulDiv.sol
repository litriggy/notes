// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.33;

// https://xn--2-umb.com/21/muldiv/

library Math {
    function mul512(uint256 x, uint256 y)
        internal
        pure
        returns (uint256 high, uint256 low)
    {
        // 중국인의 나머지 정리로 x * y 계산
        // x * y = high * 2^256 + low

        // https://xn--2-umb.com/17/chinese-remainder-theorem/
        // x0 = (x * y) mod 2^256
        // x1 = (x * y) mod (2^256 - 1)
        // low = x0
        // high = x1 - x0 - c, x1 < x0이면 c = 1, 아니면 c = 0
        assembly ("memory-safe") {
            // x1 = (x * y) mod (2^256 - 1)
            let mm := mulmod(x, y, not(0))
            // x0 = (x * y) mod 2^256
            low := mul(x, y)
            // x1 - x0 - c
            high := sub(sub(mm, low), lt(mm, low))
        }
    }

    function mulDiv(uint256 x, uint256 y, uint256 d)
        internal
        pure
        returns (uint256 result)
    {
        unchecked {
            (uint256 high, uint256 low) = mul512(x, y);

            // 256 bits / 256 bits
            if (high == 0) {
                return low / d;
            }

            // 몫이 2^256 미만인지 확인
            // (high * 2^256 + low) / d < 2^256
            // high + low / 2^256 < d
            // high + low / 2^256 < high + 1 <= d < d + 1
            // high < d
            require(high < d, "high >= denominator");

            // 512 bits / 256 bits

            // 1~3단계 설명(역순)
            // 3. d의 곱셈 역원 d_inv를 구해 x * y / d 계산
            // x * y * d_inv 반환
            // 2. d_inv가 존재하려면 d가 홀수여야 함
            // 1. d_inv로 x * y / d를 정확히 계산하려면 나머지 없이 나누어떨어져야 함

            // 1. high와 low에서 나머지를 빼 나누어떨어지도록 만듦

            // 나머지를 빼도 몫이 바뀌지 않는 이유
            // x * y / d = q이고 나머지가 r이면
            // x * y = q * d + r, 0 <= r < d
            //      x * y / d = q + r / d
            // floor(x * y / d) = floor(q + r / d) = q (정수 나눗셈에서는 r / d = 0)
            // (x * y - r) / d = q = floor(x * y / d)
            uint256 rem;
            assembly ("memory-safe") {
                // mulmod로 나머지 계산
                rem := mulmod(x, y, d)

                // 512비트 수에서 256비트 수를 뺌
                high := sub(high, gt(rem, low))
                low := sub(low, rem)
            }

            // 2. d에서 2의 거듭제곱 인수를 분리하고, d의 약수인 2의 거듭제곱 중 최댓값 계산
            // 항상 >= 1. https://cs.stackexchange.com/q/138556/92363. 참고
            uint256 twos = d & (0 - d);
            assembly ("memory-safe") {
                // d를 twos로 나눔
                d := div(d, twos)

                // [high low]를 twos로 나눔
                low := div(low, twos)

                // twos를 2²⁵⁶ / twos로 바꿈. twos가 0이면 1이 됨
                // 2^256 / 2^k
                twos := add(div(sub(0, twos), twos), 1)
            }

            // high의 비트를 low로 이동
            // d의 약수인 2의 거듭제곱 중 최댓값을 2^k로 둠
            // low = high * 2^256 / 2^k + low / 2^k
            // - high와 low의 비트를 모두 오른쪽으로 k칸 이동
            // - high * 2^256 / 2^k에서 오버플로가 발생할 수 있음
            // - 하지만 오버플로는 문제가 되지 않음
            //   z = high * 2^256 / 2^k + low / 2^k로 두고
            //   d = d / 2^k로 다시 대입
            //   일반 나눗셈
            //     z / d = q
            //     따라서 z = q * d
            //   곱셈 역원으로 나누기
            //     (z mod 2^256) * d_inv mod 2^256
            //   = ((q * d) mod 2^256) * d_inv mod 2^256
            //   =  (q * d * d_inv) mod 2^256
            //   = q mod 2^256
            low |= high * twos;

            // 3. mod 2²⁵⁶에서 d의 역원을 구함. 이제 d가 홀수이므로
            // d * inv ≡ 1 mod 2²⁵⁶인 역원이 존재함. 처음 4비트가 정확한
            // 초깃값부터 역원을 계산함. 즉, d * inv ≡ 1 mod 2⁴.
            uint256 inv = (3 * d) ^ 2;

            // Newton-Raphson 반복법으로 정밀도를 높임. Hensel의 보조정리에 따라
            // 모듈러 연산에서도 성립하며, 단계마다 정확한 비트 수가 두 배로 늘어남
            inv *= 2 - d * inv; // inv mod 2⁸
            inv *= 2 - d * inv; // inv mod 2¹⁶
            inv *= 2 - d * inv; // inv mod 2³²
            inv *= 2 - d * inv; // inv mod 2⁶⁴
            inv *= 2 - d * inv; // inv mod 2¹²⁸
            inv *= 2 - d * inv; // inv mod 2²⁵⁶

            // 이제 나누어떨어지므로 d의 모듈러 역원을 곱해 나눗셈을 수행할 수 있음
            // mod 2²⁵⁶에서 올바른 결과를 얻으며, 사전 조건이 결과가
            // 2²⁵⁶ 미만임을 보장하므로 이것이 최종 결과임. 결과의 상위 비트를 계산할 필요가 없고
            // high도 더는 필요하지 않음
            result = low * inv;
            return result;
        }
    }
}
