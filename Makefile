SHELL := /bin/bash

SWIFT := swift
XCODEBUILD := xcodebuild
XCODEGEN := xcodegen
PRODUCT_APP := KumoApp
PRODUCT_CLI := kumo
SCHEME_APP := KumoApp
SCHEME_PACKAGE := Kumo-Package
PROJECT := Kumo.xcodeproj
DERIVED_DATA := build
APP_PATH_DEBUG := $(DERIVED_DATA)/Build/Products/Debug/Kumo.app
APP_PATH_RELEASE := $(DERIVED_DATA)/Build/Products/Release/Kumo.app
DESTINATION ?= platform=macOS

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available commands.
	@awk 'BEGIN {FS = ":.*##"; printf "Kumo development commands:\n\n"} /^[a-zA-Z0-9_-]+:.*##/ {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: generate
generate: ## Regenerate the Xcode project from project.yml using XcodeGen.
	$(XCODEGEN) generate

.PHONY: app
app: generate ## Build the Kumo .app bundle in Debug to build/Build/Products/Debug.
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME_APP) -configuration Debug -derivedDataPath $(DERIVED_DATA) build

.PHONY: app-release
app-release: generate ## Build the Kumo .app bundle in Release to build/Build/Products/Release.
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME_APP) -configuration Release -derivedDataPath $(DERIVED_DATA) build

.PHONY: dev
dev: app ## Build and open the Kumo .app bundle.
	open $(APP_PATH_DEBUG)

.PHONY: dev-cli
dev-cli: ## Run the SwiftUI macOS app via swift run (no .app bundle).
	$(SWIFT) run $(PRODUCT_APP)

.PHONY: check
check: build test cli-status ## Build with Xcode, test, and verify the CLI status output.

.PHONY: build
build: app ## Build the Kumo .app bundle (alias for `make app`).

.PHONY: xcode-list
xcode-list: generate ## List Xcode schemes.
	$(XCODEBUILD) -project $(PROJECT) -list

.PHONY: xcode-build
xcode-build: app ## Build the KumoApp scheme via xcodebuild.

.PHONY: xcode-test
xcode-test: ## Run package tests via xcodebuild.
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
	rm -rf $(DERIVED_DATA)

.PHONY: xcode-clean
xcode-clean: ## Clean the KumoApp scheme via xcodebuild.
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME_APP) -configuration Debug clean

.PHONY: reset-local-state
reset-local-state: ## Remove local Kumo application support data.
	rm -rf "$$HOME/Library/Application Support/Kumo"
