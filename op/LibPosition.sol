// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

using LibPosition for Position global;

/// @notice `Position`은 게임 트리에서 클레임의 위치를 나타낸다.
/// @dev "일반화 인덱스"로 표현한다. 최상위 비트는 트리의 깊이를 나타내고,
/// 나머지 비트는 고유한 비트 패턴을 이룬다.
/// 이 방식으로 트리의 각 노드를 고유하게 식별할 수 있다.
/// 수식은 2^{depth} + indexAtDepth이다.
type Position is uint128;

/// @title LibPosition
/// @notice `Position` 타입을 다루는 보조 함수를 제공한다.
library LibPosition {
    /// @notice `MAX_POSITION_BITLEN`은 `Position` 타입과 이 라이브러리의 구현이
    ///         안전하게 지원할 수 있는 비트 수다.
    uint8 internal constant MAX_POSITION_BITLEN = 126;

    /// @notice 일반화 인덱스 (2^{depth} + indexAtDepth)를 계산한다.
    /// @param _depth 위치의 깊이.
    /// @param _indexAtDepth 해당 깊이에서의 인덱스.
    /// @return position_ 계산한 일반화 인덱스.
    function wrap(uint8 _depth, uint128 _indexAtDepth)
        internal
        pure
        returns (Position position_)
    {
        assembly {
            // gindex = 2^{_depth} + _indexAtDepth
            position_ := add(shl(_depth, 1), _indexAtDepth)
        }
    }

    /// @notice `Position` 타입에서 `depth`를 추출한다.
    /// @param _position `depth`를 구할 일반화 인덱스.
    /// @return depth_ `position` gindex의 `depth`.
    /// @custom:attribution Solady <https://github.com/Vectorized/Solady>
    function depth(Position _position) internal pure returns (uint8 depth_) {
        // gindex의 깊이를 나타내는 최상위 비트 오프셋을 반환한다.
        assembly {
            depth_ :=
                or(depth_, shl(6, lt(0xffffffffffffffff, shr(depth_, _position))))
            depth_ := or(depth_, shl(5, lt(0xffffffff, shr(depth_, _position))))

            // 나머지 32비트에는 De Bruijn 조회를 사용한다.
            _position := shr(depth_, _position)
            _position := or(_position, shr(1, _position))
            _position := or(_position, shr(2, _position))
            _position := or(_position, shr(4, _position))
            _position := or(_position, shr(8, _position))
            _position := or(_position, shr(16, _position))

            depth_ :=
                or(
                    depth_,
                    byte(
                        shr(251, mul(_position, shl(224, 0x07c4acdd))),
                        0x0009010a0d15021d0b0e10121619031e080c141c0f111807131b17061a05041f
                    )
                )
        }
    }

    /// @notice `Position` 타입에서 `indexAtDepth`를 추출한다.
    ///         `indexAtDepth`는 이진 트리의 특정 깊이에서 왼쪽부터 0으로 시작하는
    ///         위치 인덱스다. 예를 들어 gindex가 2이면 `depth` = 1이고
    ///         `indexAtDepth` = 0이다.
    /// @param _position `indexAtDepth`를 구할 일반화 인덱스.
    /// @return indexAtDepth_ `position` gindex의 `indexAtDepth`.
    function indexAtDepth(Position _position)
        internal
        pure
        returns (uint128 indexAtDepth_)
    {
        // p_{msb-1}...p_{0} 비트를 반환한다. gindex에서 2^{depth}를 제거해
        // `indexAtDepth`만 남긴다.
        uint256 msb = depth(_position);
        assembly {
            indexAtDepth_ := sub(_position, shl(msb, 1))
        }
    }

    /// @notice `_position`의 왼쪽 자식을 구한다.
    /// @param _position 왼쪽 자식을 구할 위치.
    /// @return left_ `position`의 왼쪽 자식 위치.
    function left(Position _position) internal pure returns (Position left_) {
        assembly {
            // left = 2 * pos
            // 예시
            //     1
            //    / \
            //   2   3
            //  /|   |\
            // 4 5   6 7
            left_ := shl(1, _position)
        }
    }

    /// @notice `_position`의 오른쪽 자식을 구한다.
    /// @param _position 오른쪽 자식을 구할 위치.
    /// @return right_ `position`의 오른쪽 자식 위치.
    function right(Position _position)
        internal
        pure
        returns (Position right_)
    {
        assembly {
            // right = 2 * pos + 1
            right_ := or(1, shl(1, _position))
        }
    }

    /// @notice `_position`의 부모 위치를 구한다.
    /// @param _position 부모를 구할 위치.
    /// @return parent_ `position`의 부모 위치.
    function parent(Position _position)
        internal
        pure
        returns (Position parent_)
    {
        assembly {
            // parent = pos / 2
            parent_ := shr(1, _position)
        }
    }

    /// @notice `position`을 기준으로 가장 깊은 곳의 맨 오른쪽 gindex를 구한다.
    ///         최대 깊이에 도달할 때까지 해당 위치에서 `right`를 호출하는 것과 같다.
    /// @param _position 가장 깊은 곳의 맨 오른쪽 gindex를 구할 기준 위치.
    /// @param _maxDepth 게임의 최대 깊이.
    /// @return rightIndex_ `position` 기준 가장 깊은 곳의 맨 오른쪽 gindex.
    function rightIndex(Position _position, uint256 _maxDepth)
        internal
        pure
        returns (Position rightIndex_)
    {
        uint256 msb = depth(_position);
        assembly {
            let remaining := sub(_maxDepth, msb)
            // 최대 깊이에서 맨 왼쪽 노드와 맨 오른쪽 노드의 차이
            // 2 ** rem * pos +  2**rem - 1
            // right 1 -> 2 * pos + 1
            // right 2 -> 2 * (2 * pos + 1) + 1           = 2**2 * pos + 2**1 + 1
            // right 3 -> 2 * (2 * (2 * pos + 1) + 1) + 1 = 2**3 * pos + 2**2 + 2**1 + 1
            // right 4 -> ...                             = 2**4 * pos + 2**3 + 2**2 + 2**1 + 1
            // right n ->                                 = 2**n * pos + 2**n - 1
            //
            // 등비수열의 합
            // 1 + 2 + .. + 2**n = (2**(n + 1) - 1) / (2 - 1)

            rightIndex_ :=
                or(shl(remaining, _position), sub(shl(remaining, 1), 1))
        }
    }

    /// @notice `position`을 기준으로 가장 깊은 곳의 맨 오른쪽 추적 인덱스를 구한다.
    ///         최대 깊이에 도달할 때까지 해당 위치에서 `right`를 호출한 뒤
    ///         그 깊이에서의 인덱스를 구하는 것과 같다.
    /// @param _position 상대 추적 인덱스를 구할 기준 위치.
    /// @param _maxDepth 게임의 최대 깊이.
    /// @return traceIndex_ `position` 기준 추적 인덱스.
    function traceIndex(Position _position, uint256 _maxDepth)
        internal
        pure
        returns (uint256 traceIndex_)
    {
        uint256 msb = depth(_position);
        assembly {
            let remaining := sub(_maxDepth, msb)
            // 오른쪽 인덱스 - 최대 깊이의 맨 왼쪽 노드
            // (2**rem * pos + (2**rem - 1)) - 2**max_depth
            traceIndex_ :=
                sub(
                    or(shl(remaining, _position), sub(shl(remaining, 1), 1)),
                    shl(_maxDepth, 1)
                )
        }
    }

    /// @notice `_position`과 같은 추적 인덱스에 커밋하는
    ///         가장 높은 조상의 위치를 구한다.
    /// @param _position 가장 높은 조상을 구할 위치.
    /// @return ancestor_ `position`과 같은 추적 인덱스에 커밋하는 가장 높은 조상.
    function traceAncestor(Position _position)
        internal
        pure
        returns (Position ancestor_)
    {
        //            1
        //      /           \
        //     2             3
        //   /   \         /   \
        //  4     5       6     7
        // pos | 추적 조상
        //   1 | 1
        //   2 | 2
        //   3 | 1
        //   4 | 4
        //   5 | 2
        //   6 | 6
        //   7 | 1

        // `_position`에서 가장 낮은 0 비트만 1로 설정한 비트 필드를 만든다.
        Position lsb;
        assembly {
            lsb := and(not(_position), add(_position, 1))
        }
        // 비트 필드에서 가장 낮은 0 비트의 인덱스를 구한다.
        uint256 msb = depth(lsb);
        // 같은 추적 인덱스에 커밋하는 가장 높은 조상은 원래 위치를
        // 가장 낮은 0 비트의 인덱스만큼 오른쪽으로 이동한 값이다.

        // 예시
        // pos = 11000100111
        // lsb = 00000001000
        // msb =        3
        // anc = 11000100

        // 위치의 이진수 표현은 트리 경로를 나타낸다.
        //    1    p = 01
        //   / \
        //  2   3
        // 10   11 <- p << 1 + (0 또는 1)
        // 자식 c가 주어졌을 때 부모를 구하는 식: p = c >> 1

        // 추적 조상 = pos의 왼쪽에 있는 가장 높은 조상
        //           = 자식에서 위쪽 + 왼쪽으로 더 갈 수 없을 때까지 이동
        //           = 짝수 또는 1이 될 때까지 2로 나누기
        //           = 마지막 비트가 0이 될 때까지 오른쪽으로 비트 이동
        //        1        <-     01
        //      /   \           /    \
        //     2     3     <-  10     11
        //    / \   / \       / \     / \
        //   4   5 6   7 <- 100 101 110 111
        assembly {
            let a := shr(msb, _position)
            // 조상의 gindex가 최솟값 1보다 작아지지 않게 한다.
            ancestor_ := or(a, iszero(a))
        }
    }

    /// @notice `_position`과 같은 추적 인덱스에 커밋하면서 `_upperBoundExclusive`보다
    ///         아래에 있는 가장 높은 조상의 위치를 구한다.
    /// @param _position 가장 높은 조상을 구할 위치.
    /// @param _upperBoundExclusive 포함하지 않는 상위 깊이 경계. 하위 트리를 벗어나지 않도록
    ///                             탐색을 멈출 위치를 정하는 데 사용한다.
    /// @return ancestor_ `position`과 같은 추적 인덱스에 커밋하는 가장 높은 조상.
    function traceAncestorBounded(
        Position _position,
        uint256 _upperBoundExclusive
    ) internal pure returns (Position ancestor_) {
        // 이 함수는 상위 경계보다 아래에 있는 위치에서만 작동한다.
        if (_position.depth() <= _upperBoundExclusive) {
            assembly {
                // `ClaimAboveSplit()` 오류로 되돌린다.
                mstore(0x00, 0xb34b5c22)
                revert(0x1C, 0x04)
            }
        }

        // 전체 트리의 추적 조상을 구한다.
        ancestor_ = traceAncestor(_position);

        // 조상이 상위 경계에 있거나 그 위에 있으면 경계 아래로 이동한다.
        // 하위 트리의 마지막 리프에 커밋하는 위치에만 해당하는
        // 특수한 경우여야 한다.
        if (ancestor_.depth() <= _upperBoundExclusive) {
            ancestor_ = ancestor_.rightIndex(_upperBoundExclusive + 1);
        }
    }

    /// @notice `_position`의 이동 위치를 구한다. 다음 위치의 왼쪽 자식이다.
    ///         1. `_isAttack`이 true이면 `_position`.
    ///         2. `_isAttack`이 false이면 `_position | 1`.
    /// @param _position 상대 공격·방어 위치를 구할 기준 위치.
    /// @param _isAttack 공격 이동인지 여부.
    /// @return move_ `position` 기준 이동 위치.
    function move(Position _position, bool _isAttack)
        internal
        pure
        returns (Position move_)
    {
        assembly {
            // 예시
            //     1
            //    / \
            //   2   3
            //  /|   |\
            // 4 5   6 7
            //
            // 공격 2 -> 4
            // 방어 2 -> 6
            //
            // 공격 -> 2 * pos
            // 방어 -> 2 * (pos + 1)
            move_ := shl(1, or(iszero(_isAttack), _position))
        }
    }

    /// @notice `Position` 타입의 값을 기반 타입인 uint128로 구한다.
    /// @param _position 값을 구할 위치.
    /// @return raw_ uint128 타입으로 표현한 `position`의 값.
    function raw(Position _position) internal pure returns (uint128 raw_) {
        assembly {
            raw_ := _position
        }
    }
}
