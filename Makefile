-include .env

.PHONY: deploy

deploy :; @forge script script/Deploy.s.sol --private-key ${PRIVATE_KEY} --rpc-url ${SEPOLIA_RPC_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --verify --legacy
#verify :; @forge verify-contract ${CONTRACT_ADDRESS} src/Synthetic.sol:Synthetic --chain sepolia
