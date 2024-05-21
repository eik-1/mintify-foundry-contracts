-include .env

.PHONY: deploy

deploy :; @forge script script/Deploy.s.sol --private-key ${PRIVATE_KEY} --rpc-url ${POLYGON_RPC_URL} --broadcast 
verify :; @forge verify-contract ${CONTRACT_ADDRESS} src/Synthetic.sol:Synthetic --chain polygon-amoy