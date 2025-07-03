# Makefile for Runner Reputation Smart Contract

# Load environment variables
-include .env

# Network configuration
NETWORK ?= filecoin_calibration
RPC_URL ?= $(FILECOIN_CALIBRATION_RPC_URL)
CHAIN_ID ?= $(FILECOIN_CALIBRATION_CHAIN_ID)
EXPLORER_URL ?= $(FILECOIN_CALIBRATION_EXPLORER_URL)

# Contract configuration
CONTRACT_NAME ?= RunnerReputation
CONTRACT_FILE ?= src/$(CONTRACT_NAME).sol
DEPLOY_SCRIPT ?= script/Deploy.s.sol

# Deployment configuration
PRIVATE_KEY ?= $(DEPLOYER_PRIVATE_KEY)
ETHERSCAN_API_KEY ?= $(FILECOIN_CALIBRATION_API_KEY)

# Foundry tools
FORGE = forge
CAST = cast
ANVIL = anvil

# Colors for output
GREEN = \033[0;32m
YELLOW = \033[0;33m
RED = \033[0;31m
NC = \033[0m # No Color

.PHONY: help install build test clean deploy verify status anvil

# Default target
all: help

## Help
help: ## Show this help message
	@echo "$(GREEN)Runner Reputation Smart Contract Makefile$(NC)"
	@echo ""
	@echo "$(YELLOW)Usage:$(NC)"
	@echo "  make [target]"
	@echo ""
	@echo "$(YELLOW)Targets:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

## Development
install: ## Install dependencies
	@echo "$(YELLOW)Installing dependencies...$(NC)"
	$(FORGE) install

build: ## Compile contracts
	@echo "$(YELLOW)Building contracts...$(NC)"
	$(FORGE) build

clean: ## Clean build artifacts
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	$(FORGE) clean

fmt: ## Format code
	@echo "$(YELLOW)Formatting code...$(NC)"
	$(FORGE) fmt

fmt-check: ## Check code formatting
	@echo "$(YELLOW)Checking code formatting...$(NC)"
	$(FORGE) fmt --check

## Testing
test: ## Run all tests
	@echo "$(YELLOW)Running tests...$(NC)"
	$(FORGE) test -vvv

test-coverage: ## Run tests with coverage
	@echo "$(YELLOW)Running tests with coverage...$(NC)"
	$(FORGE) coverage

test-gas: ## Run tests with gas reporting
	@echo "$(YELLOW)Running tests with gas reporting...$(NC)"
	$(FORGE) test --gas-report

test-watch: ## Watch and run tests on file changes
	@echo "$(YELLOW)Watching for file changes...$(NC)"
	$(FORGE) test --watch

snapshot: ## Create gas snapshot
	@echo "$(YELLOW)Creating gas snapshot...$(NC)"
	$(FORGE) snapshot

## Local Development
anvil: ## Start local blockchain
	@echo "$(YELLOW)Starting local blockchain...$(NC)"
	$(ANVIL) --chain-id 31337 --port 8545

deploy-local: ## Deploy to local network
	@echo "$(YELLOW)Deploying to local network...$(NC)"
	$(FORGE) script $(DEPLOY_SCRIPT) --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

## Filecoin Calibration Network
deploy-calibration: check-env ## Deploy to Filecoin Calibration testnet
	@echo "$(YELLOW)Deploying to Filecoin Calibration testnet...$(NC)"
	$(FORGE) script $(DEPLOY_SCRIPT) \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--skip-simulation \
		--ffi \
		-vvvv

deploy-calibration-verify: check-env check-api-key ## Deploy to Filecoin Calibration with verification
	@echo "$(YELLOW)Deploying to Filecoin Calibration with verification...$(NC)"
	$(FORGE) script $(DEPLOY_SCRIPT) \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--chain-id $(CHAIN_ID) \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		--skip-simulation \
		--ffi \
		-vvvv

deploy-calibration-dry: ## Dry run deployment to Filecoin Calibration
	@echo "$(YELLOW)Dry run deployment to Filecoin Calibration...$(NC)"
	$(FORGE) script $(DEPLOY_SCRIPT) --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY)



verify-calibration: ## Verify contract on Filecoin Calibration
	@echo "$(YELLOW)Verifying contract on Filecoin Calibration...$(NC)"
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "$(RED)Error: CONTRACT_ADDRESS not set. Use: make verify-calibration CONTRACT_ADDRESS=0x...$(NC)"; \
		exit 1; \
	fi
	$(FORGE) verify-contract \
		--rpc-url $(RPC_URL) \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		--chain-id $(CHAIN_ID) \
		$(CONTRACT_ADDRESS) \
		$(CONTRACT_FILE):$(CONTRACT_NAME)

## Network Interaction
get-balance: ## Get balance of deployer address
	@echo "$(YELLOW)Getting balance...$(NC)"
	@if [ -z "$(DEPLOYER_ADDRESS)" ]; then \
		echo "$(RED)Error: DEPLOYER_ADDRESS not set in .env file$(NC)"; \
		exit 1; \
	fi
	$(CAST) balance $(DEPLOYER_ADDRESS) --rpc-url $(RPC_URL)

get-nonce: ## Get nonce of deployer address
	@echo "$(YELLOW)Getting nonce...$(NC)"
	@if [ -z "$(DEPLOYER_ADDRESS)" ]; then \
		echo "$(RED)Error: DEPLOYER_ADDRESS not set in .env file$(NC)"; \
		exit 1; \
	fi
	$(CAST) nonce $(DEPLOYER_ADDRESS) --rpc-url $(RPC_URL)

get-gas-price: ## Get current gas price
	@echo "$(YELLOW)Getting gas price...$(NC)"
	$(CAST) gas-price --rpc-url $(RPC_URL)

## Contract Interaction (requires CONTRACT_ADDRESS)
call-network-stats: ## Call getNetworkStats function
	@echo "$(YELLOW)Getting network stats...$(NC)"
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "$(RED)Error: CONTRACT_ADDRESS not set. Use: make call-network-stats CONTRACT_ADDRESS=0x...$(NC)"; \
		exit 1; \
	fi
	$(CAST) call $(CONTRACT_ADDRESS) "getNetworkStats()" --rpc-url $(RPC_URL)

call-runner-profile: ## Call getRunnerProfile function (requires RUNNER_ID)
	@echo "$(YELLOW)Getting runner profile...$(NC)"
	@if [ -z "$(CONTRACT_ADDRESS)" ] || [ -z "$(RUNNER_ID)" ]; then \
		echo "$(RED)Error: CONTRACT_ADDRESS and RUNNER_ID must be set$(NC)"; \
		echo "$(RED)Usage: make call-runner-profile CONTRACT_ADDRESS=0x... RUNNER_ID=runner123$(NC)"; \
		exit 1; \
	fi
	$(CAST) call $(CONTRACT_ADDRESS) "getRunnerProfile(string)" $(RUNNER_ID) --rpc-url $(RPC_URL)

register-runner: ## Register a new runner (requires RUNNER_ID and WALLET_ADDRESS)
	@echo "$(YELLOW)Registering runner...$(NC)"
	@if [ -z "$(CONTRACT_ADDRESS)" ] || [ -z "$(RUNNER_ID)" ] || [ -z "$(WALLET_ADDRESS)" ]; then \
		echo "$(RED)Error: CONTRACT_ADDRESS, RUNNER_ID, and WALLET_ADDRESS must be set$(NC)"; \
		echo "$(RED)Usage: make register-runner CONTRACT_ADDRESS=0x... RUNNER_ID=runner123 WALLET_ADDRESS=0x...$(NC)"; \
		exit 1; \
	fi
	$(CAST) send $(CONTRACT_ADDRESS) "registerRunner(string,address)" $(RUNNER_ID) $(WALLET_ADDRESS) \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

## Environment checks
check-env:
	@if [ -z "${PRIVATE_KEY}" ]; then \
		echo "$(RED)Error: DEPLOYER_PRIVATE_KEY is required for network deployment$(NC)"; \
		exit 1; \
	fi

check-api-key:
	@if [ -z "${ETHERSCAN_API_KEY}" ]; then \
		echo "$(RED)Error: FILECOIN_CALIBRATION_API_KEY is required for verification$(NC)"; \
		echo "$(YELLOW)Get API key from Blockscout or use 'make deploy-calibration' for deployment without verification$(NC)"; \
		exit 1; \
	fi

check-contract:
	@if [ -z "${CONTRACT_ADDRESS}" ]; then \
		echo "$(RED)Error: CONTRACT_ADDRESS is required for this operation$(NC)"; \
		exit 1; \
	fi

setup-env: ## Copy .env.example to .env
	@echo "$(YELLOW)Setting up environment file...$(NC)"
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "$(GREEN).env file created from .env.example$(NC)"; \
		echo "$(YELLOW)Please edit .env file with your configuration$(NC)"; \
	else \
		echo "$(RED).env file already exists$(NC)"; \
	fi

show-info: ## Show project information
	@echo "$(GREEN)==================== PROJECT INFO ====================$(NC)"
	@echo "$(YELLOW)Contract Name:$(NC) $(CONTRACT_NAME)"
	@echo "$(YELLOW)Contract File:$(NC) $(CONTRACT_FILE)"
	@echo "$(YELLOW)Deploy Script:$(NC) $(DEPLOY_SCRIPT)"
	@echo "$(YELLOW)Network:$(NC) $(NETWORK)"
	@echo "$(YELLOW)Chain ID:$(NC) $(CHAIN_ID)"
	@echo "$(YELLOW)RPC URL:$(NC) $(RPC_URL)"
	@echo "$(YELLOW)Explorer:$(NC) $(EXPLORER_URL)"
	@echo "$(GREEN)=====================================================$(NC)"

## Advanced
slither: ## Run Slither static analysis (requires slither installation)
	@echo "$(YELLOW)Running Slither analysis...$(NC)"
	slither .

mythril: ## Run Mythril security analysis (requires mythril installation)
	@echo "$(YELLOW)Running Mythril analysis...$(NC)"
	myth analyze $(CONTRACT_FILE)

estimate-gas: ## Estimate deployment gas cost
	@echo "$(YELLOW)Estimating deployment gas cost...$(NC)"
	$(FORGE) script $(DEPLOY_SCRIPT) --rpc-url $(RPC_URL)

## Cleanup
remove-modules: ## Remove all git submodules (forge dependencies)
	@echo "$(YELLOW)Removing forge dependencies...$(NC)"
	rm -rf lib/

reinstall: clean remove-modules install build ## Clean reinstall of dependencies
	@echo "$(GREEN)Clean reinstall completed$(NC)" 