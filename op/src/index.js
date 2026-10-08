const optimism = require("@eth-optimism/sdk")
const ethers = require("ethers")

const PRIVATE_KEY = process.env.PRIVATE_KEY
const L2_TX = process.env.L2_TX

const L1_RPC = "https://rpc.ankr.com/eth_sepolia"
const L2_RPC = "https://sepolia.optimism.io"
// Sepolia는 11155111, Ethereum은 1
const L1_CHAIN_ID = 11155111
// OP Sepolia는 11155420, OP Mainnet은 10
const L2_CHAIN_ID = 11155420

const WAIT_TIME = 60

function sleep(ms) {
  return new Promise((resolve) => setTimeout(() => resolve(), ms))
}

async function main() {
  // RPC 프로바이더와 지갑 생성
  const l1_provider = new ethers.providers.StaticJsonRpcProvider(L1_RPC)
  const l2_provider = new ethers.providers.StaticJsonRpcProvider(L2_RPC)
  const l1_wallet = new ethers.Wallet(PRIVATE_KEY, l1_provider)
  const l2_wallet = new ethers.Wallet(PRIVATE_KEY, l2_provider)

  // CrossChainMessenger 인스턴스 생성
  const messenger = new optimism.CrossChainMessenger({
    l1ChainId: L1_CHAIN_ID,
    l2ChainId: L2_CHAIN_ID,
    l1SignerOrProvider: l1_wallet,
    l2SignerOrProvider: l2_wallet,
  })

  // 메시지를 증명할 준비가 될 때까지 대기
  console.log("Wait for message status...")
  await messenger.waitForMessageStatus(
    L2_TX,
    optimism.MessageStatus.READY_TO_PROVE
  )

  // L1에서 메시지 증명
  console.log("Prove message on L1...")
  await messenger.proveMessage(L2_TX)

  // 메시지를 중계할 준비가 될 때까지 대기
  // 참고:
  // 오류 증명 기간이 지나야 이 단계로 넘어갈 수 있음
  // OP Sepolia에서는 몇 초만 소요
  // OP Mainnet에서는 7일 소요
  console.log("Wait for message status...")
  await messenger.waitForMessageStatus(
    L2_TX,
    optimism.MessageStatus.READY_FOR_RELAY
  )

  console.log(`Sleep ${WAIT_TIME} seconds`)
  await sleep(WAIT_TIME * 1000)

  // L1에서 메시지 중계
  console.log("Finalize...")
  await messenger.finalizeMessage(L2_TX)

  // 메시지가 중계될 때까지 대기
  console.log("Wait for message status...")
  await messenger.waitForMessageStatus(L2_TX, optimism.MessageStatus.RELAYED)
}

main()
