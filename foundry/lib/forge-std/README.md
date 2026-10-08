<a id="forge-standard-library--ci-status"></a>
# Forge Standard Library • [![CI 상태](https://github.com/foundry-rs/forge-std/actions/workflows/ci.yml/badge.svg)](https://github.com/foundry-rs/forge-std/actions/workflows/ci.yml)

Forge Standard Library는 [Forge와 Foundry](https://github.com/foundry-rs/foundry)에서 쓸 수 있는 유용한 컨트랙트와 라이브러리 모음입니다. Forge의 치트코드로 테스트를 더 쉽고 빠르게 작성하고, 치트코드도 더 편리하게 사용할 수 있습니다.

**[📖 Foundry Book (Forge-Std 가이드)](https://getfoundry.sh/reference/forge-std/overview/)에서 Forge-Std 사용법을 알아보세요.**

<a id="install"></a>
## 설치

```bash
forge install foundry-rs/forge-std
```

<a id="contracts"></a>
## 컨트랙트
### stdError

오류와 리버트를 다루는 보조 컨트랙트입니다. 컴파일러 내장 오류를 모두 제공하므로 Forge의 `expectRevert` 치트코드를 쓸 때 특히 유용합니다.

전체 오류 코드는 컨트랙트에서 확인하세요.

<a id="example-usage"></a>
#### 사용 예시

```solidity

import "forge-std/Test.sol";

contract TestContract is Test {
    ErrorsTest test;

    function setUp() public {
        test = new ErrorsTest();
    }

    function testExpectArithmetic() public {
        vm.expectRevert(stdError.arithmeticError);
        test.arithmeticError(10);
    }
}

contract ErrorsTest {
    function arithmeticError(uint256 a) public {
        a = a - 100;
    }
}
```

### stdStorage

사용 편의를 위한 오버로드가 많아 컨트랙트 규모가 꽤 큽니다. 주로 `record`와 `accesses` 치트코드를 감싸는 래퍼로, 스토리지 레이아웃을 몰라도 특정 변수의 스토리지 슬롯을 *항상* 찾아 값을 쓸 수 있습니다. 다만 _반드시_ 주의할 점이 있습니다. 여러 변수가 한 슬롯을 공유하는 패킹된 스토리지에서는 슬롯을 찾을 수 있어도 해당 변수에 안전하게 값을 쓸 수는 없습니다. 패킹된 슬롯에 쓰기를 시도하면 초기화되지 않은 슬롯(`bytes32(0)`)을 제외하고는 실행 중 오류가 발생합니다.

함수 호출 중 발생하는 모든 `SLOAD`와 `SSTORE`를 기록하는 방식으로 동작합니다. 읽거나 쓴 슬롯이 하나뿐이면 해당 슬롯을 바로 반환합니다. 슬롯이 여러 개라면 내부에서 하나씩 순회하며 확인합니다(사용자가 `depth` 매개변수를 전달했다고 가정합니다). 변수가 구조체라면 필드의 깊이를 나타내는 `depth` 매개변수를 전달할 수 있습니다.

예를 들면 다음과 같습니다.
```solidity
struct T {
    // 깊이 0
    uint256 a;
    // 깊이 1
    uint256 b;
}
```

<a id="example-usage-1"></a>
#### 사용 예시

```solidity
import "forge-std/Test.sol";

contract TestContract is Test {
    using stdStorage for StdStorage;

    Storage test;

    function setUp() public {
        test = new Storage();
    }

    function testFindExists() public {
        // public 변수 `exists`의 슬롯을 찾으려면
        // `find` 명령에 함수 선택자만 전달하면 됩니다.
        uint256 slot = stdstore.target(address(test)).sig("exists()").find();
        assertEq(slot, 0);
    }

    function testWriteExists() public {
        // public 변수 `exists`의 슬롯에 값을 쓰려면
        // `checked_write` 명령에 함수 선택자만 전달하면 됩니다.
        stdstore.target(address(test)).sig("exists()").checked_write(100);
        assertEq(test.exists(), 100);
    }

    // 어셈블리로 지정한 저장 위치 등 임의의 스토리지 레이아웃도 지원합니다.
    function testFindHidden() public {
        // `hidden`은 임의의 바이트 해시라서 슬롯을 순회해서는
        // 찾을 수 없지만, 이 방식으로는 찾을 수 있습니다.
        // 문자열 대신 선택자를 사용할 수도 있습니다.
        uint256 slot = stdstore.target(address(test)).sig(test.hidden.selector).find();
        assertEq(slot, uint256(keccak256("my.random.var")));
    }

    // 매핑을 대상으로 찾을 때는 검색에 필요한 키를 전달해야 합니다.
    // 예를 들면 다음과 같습니다.
    function testFindMapping() public {
        uint256 slot = stdstore
            .target(address(test))
            .sig(test.map_addr.selector)
            .with_key(address(this))
            .find();
        // `Storage` 생성자에서 매핑의 이 주소에 해당하는 값을 1로 설정했으므로
        // 슬롯을 읽으면 값이 1이어야 합니다.
        assertEq(uint(vm.load(address(test), bytes32(slot))), 1);
    }

    // 대상이 구조체라면 필드의 깊이를 지정할 수 있습니다.
    function testFindStruct() public {
        // 참고: depth 매개변수에서 0은 0번째 필드, 1은 1번째 필드를 뜻합니다.
        uint256 slot_for_a_field = stdstore
            .target(address(test))
            .sig(test.basicStruct.selector)
            .depth(0)
            .find();

        uint256 slot_for_b_field = stdstore
            .target(address(test))
            .sig(test.basicStruct.selector)
            .depth(1)
            .find();

        assertEq(uint(vm.load(address(test), bytes32(slot_for_a_field))), 1);
        assertEq(uint(vm.load(address(test), bytes32(slot_for_b_field))), 2);
    }
}

// 복잡한 스토리지 컨트랙트
contract Storage {
    struct UnpackedStruct {
        uint256 a;
        uint256 b;
    }

    constructor() {
        map_addr[msg.sender] = 1;
    }

    uint256 public exists = 1;
    mapping(address => uint256) public map_addr;
    // mapping(address => Packed) public map_packed;
    mapping(address => UnpackedStruct) public map_struct;
    mapping(address => mapping(address => uint256)) public deep_map;
    mapping(address => mapping(address => UnpackedStruct)) public deep_map_struct;
    UnpackedStruct public basicStruct = UnpackedStruct({
        a: 1,
        b: 2
    });

    function hidden() public view returns (bytes32 t) {
        // 찾기 매우 어려운 스토리지 슬롯
        bytes32 slot = keccak256("my.random.var");
        assembly {
            t := sload(slot)
        }
    }
}
```

### stdCheats

여러 치트코드를 개발자가 더 편하게 쓰도록 감싼 래퍼입니다. 현재는 `prank` 관련 함수만 있습니다. `prank`를 호출하면 해당 주소에 ETH도 들어갈 것이라 생각할 수 있지만, 안전을 위해 그렇게 동작하지 않습니다. `hoax`는 잔액을 덮어쓰므로 잔액을 예상할 수 있는 주소에만 사용해야 합니다. 주소에 이미 ETH가 있다면 `prank`만 사용하세요. 잔액을 명시적으로 바꾸려면 `deal`을 사용하세요. 두 작업을 함께 하려면 `hoax`를 사용하면 됩니다.


<a id="example-usage-2"></a>
#### 사용 예시:
```solidity

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// stdCheats 상속
contract StdCheatsTest is Test {
    Bar test;
    function setUp() public {
        test = new Bar();
    }

    function testHoax() public {
        // `hoax`는 대상 주소에 ETH를 지급한 뒤
        // `prank`를 호출합니다.
        hoax(address(1337));
        test.bar{value: 100}(address(1337));

        // 오버로드를 사용하면 주소의 초기 ETH 잔액을
        // 지정할 수 있습니다.
        hoax(address(1337), 1);
        test.bar{value: 1}(address(1337));
    }

    function testStartHoax() public {
        // `startHoax`는 대상 주소에 ETH를 지급한 뒤
        // `startPrank`를 호출합니다.
        //
        // ETH 금액을 지정할 수 있는 오버로드도 있습니다.
        startHoax(address(1337));
        test.bar{value: 100}(address(1337));
        test.bar{value: 100}(address(1337));
        vm.stopPrank();
        test.bar(address(this));
    }
}

contract Bar {
    function bar(address expectedSender) public payable {
        require(msg.sender == expectedSender, "!prank");
    }
}
```

<a id="std-assertions"></a>
### Std 단언문

다양한 단언문을 제공합니다.

### `console.log`

사용법은 [Hardhat](https://hardhat.org/hardhat-network/reference/#console-log)과 같습니다.
아래처럼 `console2.sol`을 사용하면 Forge 트레이스에서 디코딩한 로그를 볼 수 있으므로 이 방식을 권장합니다.

```solidity
// Test.sol을 통해 간접적으로 가져오기
import "forge-std/Test.sol";
// 또는 직접 가져오기
import "forge-std/console2.sol";
...
console2.log(someValue);
```

Hardhat과 호환되어야 한다면 기본 `console.sol`을 사용해야 합니다.
`console.sol`의 버그로 인해 `uint256` 또는 `int256` 타입을 쓰는 로그는 Forge 트레이스에서 올바르게 디코딩되지 않습니다.

```solidity
// Test.sol을 통해 간접적으로 가져오기
import "forge-std/Test.sol";
// 또는 직접 가져오기
import "forge-std/console.sol";
...
console.log(someValue);
```

<a id="contributing"></a>
## 기여하기

자세한 내용은 [기여 안내](./CONTRIBUTING.md)를 확인하세요.

<a id="getting-help"></a>
## 도움받기

먼저 [문서](https://book.getfoundry.sh)에서 질문의 답을 찾아보세요.

답을 찾지 못했다면:

-   [지원 Telegram](https://t.me/foundry_support)에 참여해 도움을 받거나
-   [토론](https://github.com/foundry-rs/foundry/discussions/new/choose)에 질문을 올리거나
-   [버그 이슈](https://github.com/foundry-rs/foundry/issues/new/choose)를 등록하세요.

기여하고 싶거나 기여자들의 논의에 참여하고 싶다면 [메인 Telegram](https://t.me/foundry_rs)에서 Foundry 개발을 함께 이야기해 보세요!

<a id="license"></a>
## 라이선스

Forge Standard Library는 [MIT](LICENSE-MIT) 또는 [Apache 2.0](LICENSE-APACHE) 라이선스로 제공됩니다.
