SHELL := /bin/bash

SWIFT := swift
XCODEBUILD := xcodebuild
PRODUCT_APP := KumoApp
PRODUCT_CLI := kumo
SCHEME_APP := KumoApp
SCHEME_PACKAGE := Kumo-Package
DESTINATION ?= platform=macOS

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available commands.
	@awk 'BEGIN {FS = ":.*##"; printf "Kumo development commands:\n\n"} /^[a-zA-Z0-9_-]+:.*##/ {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: dev
dev: run-app ## Launch the SwiftUI macOS app for local development.

.PHONY: check
check: build test cli-status ## Build with Xcode, test, and verify the CLI status output.

.PHONY: build
build: xcode-build ## Build the macOS app with Xcode CLI.

.PHONY: xcode-list
xcode-list: ## List Xcode schemes.
	$(XCODEBUILD) -list

.PHONY: xcode-build
xcode-build: ## Build the KumoApp scheme with Xcode CLI.
	$(XCODEBUILD) -scheme $(SCHEME_APP) -destination '$(DESTINATION)' build

.PHONY: xcode-test
xcode-test: ## Run package tests with Xcode CLI.
	$(XCODEBUILD) -scheme $(SCHEME_PACKAGE) -destination '$(DESTINATION)' test

.PHONY: swift-build
swift-build: ## Build all Swift package products in debug mode.
	$(SWIFT) build

.PHONY: build-release
build-release: ## Build all Swift package products in release mode.
	$(SWIFT) build -c release

.PHONY: test
test: xcode-test ## Run unit tests with Xcode CLI.

.PHONY: swift-test
swift-test: ## Run unit tests with SwiftPM.
	$(SWIFT) test

.PHONY: run-app
run-app: ## Run the SwiftUI macOS app.
	$(SWIFT) run $(PRODUCT_APP)

.PHONY: run-cli
run-cli: ## Run the Kumo CLI. Override ARGS, for example: make run-cli ARGS="status --json".
	$(SWIFT) run $(PRODUCT_CLI) $(ARGS)

.PHONY: cli-status
cli-status: ## Print CLI status as JSON.
	$(SWIFT) run $(PRODUCT_CLI) status --json

.PHONY: cli-sysproxy-dry-run
cli-sysproxy-dry-run: ## Show system proxy commands without applying them.
	$(SWIFT) run $(PRODUCT_CLI) sysproxy on --dry-run --json

.PHONY: docs
docs: ## List technical documentation files.
	@printf "Technical docs:\n"
	@ls docs/*.md

.PHONY: clean
clean: ## Remove Swift build artifacts.
	$(SWIFT) package clean

.PHONY: xcode-clean
xcode-clean: ## Clean the KumoApp scheme with Xcode CLI.
	$(XCODEBUILD) -scheme $(SCHEME_APP) -destination '$(DESTINATION)' clean

.PHONY: reset-local-state
reset-local-state: ## Remove local Kumo application support data.
	rm -rf "$$HOME/Library/Application Support/Kumo"
