```shell
# L2에서 L1으로 메시지 전송
L2_TX=0x3592c40fbd8577993e307b0c5ed534482c5dc5a3bb996d540300b8542a5bf85f
env $(cat .env) L2_TX=$L2_TX node src/index.js

# L1에서 L2로 ERC20 입금
env $(cat .env) node src/erc20_deposit.js

# L2에서 L1으로 ERC20 출금
env $(cat .env) node src/erc20_withdraw.js
```

컨트랙트

https://github.com/ethereum-optimism/optimism/tree/develop/packages/contracts-bedrock/src
