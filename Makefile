-include .env

.PHONY: deploy

deploy :; @forge script script/Deploy.s.sol --private-key ${PRIVATE_KEY} --rpc-url ${SEPOLIA_RPC_URL} --broadcast --gas-limit 5000000 --gas-price 20000000000
verify :; @forge verify-contract ${CONTRACT_ADDRESS} src/Synthetic.sol:Synthetic --chain sepolia
