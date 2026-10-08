// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.33;

interface IRebase {
    function transfer(address dst, uint256 amt) external;
    function transferFrom(address src, address dst, uint256 amt) external;
    function calcShares(uint256 underlying)
        external
        view
        returns (uint256 shares);
    function calcUnderlying(uint256 shares)
        external
        view
        returns (uint256 underlying);
}

contract Wrap {
    IRebase public immutable re;
    mapping(address => uint256) public shares;

    constructor(address _re) {
        re = IRebase(_re);
    }

    // 기초 토큰과 리베이스 토큰
    // U = 기초 토큰 잔액
    // R = 리베이스 토큰 잔액
    // R = U

    // 리베이스 지분
    // S = 리베이스 내부 지분
    // X = 리베이스 비율 배수
    // R = S * X

    // 리베이스와 래핑
    // W = 래핑 지분
    // W = S = R / X

    function wrap(uint256 r) external {
        // W = S = R / X
        uint256 w = re.calcShares(r);
        shares[msg.sender] += w;
        re.transferFrom(msg.sender, address(this), r);
    }

    function unwrap(uint256 w) external {
        // R = S * X = W * X
        uint256 r = re.calcUnderlying(w);
        shares[msg.sender] -= w;
        re.transfer(msg.sender, r);
    }
}
