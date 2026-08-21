# Single entry point for the checks CI runs, so the same commands work locally.
# Each target mirrors one CI job in .github/workflows/ci.yml; when a job changes
# there, change it here too or the two stop agreeing.

.DEFAULT_GOAL := help
.PHONY: help setup check lint format format-check backend landing android test integration db-migrate db-status xcode clean lint-ios format-ios format-check-ios ios

BACKEND := backend
LANDING := landing
ANDROID := ios/android-client
IOS     := ios

# What the iOS format targets diff against. Override for a branch that is not
# based on main:  make format-ios BASE_REF=origin/release-1.4
BASE_REF ?= origin/main

help: ## List available targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk -F':.*?## ' '{printf "  \033[1m%-17s\033[0m %s\n", $$1, $$2}'

# npm ci, not npm install: it installs exactly the lockfile and fails if
# package.json and the lock disagree, which is what you want before a build.
# The Xcode project step is skipped on a non-macOS machine rather than failing —
# the backend and landing site are developed on Linux too.
setup: ## Install dependencies and generate the Xcode project
	cd $(BACKEND) && npm ci && npx prisma generate
	cd $(LANDING) && npm ci
	@command -v xcodegen >/dev/null 2>&1 \
	  && (cd $(IOS) && xcodegen generate) \
	  || echo "  xcodegen not found — skipping Xcode project (see docs/runbooks/ios-build-and-release.md)"

check: lint backend landing ## Everything CI checks that does not need a macOS runner

lint: ## ESLint across the backend and the landing site
	cd $(BACKEND) && npm run lint
	cd $(LANDING) && npm run lint

# Formatting is not yet enforced tree-wide: backend/src predates the Prettier
# config and reformatting it is ~13k lines of pure whitespace. CI checks only the
# files a change touches (the `format` job), so the formatted share grows instead
# of arriving as one unreviewable commit. See CONTRIBUTING.md.
format: ## Format everything Prettier owns, in place
	cd $(BACKEND) && npm run format
	cd $(LANDING) && npm run format

format-check: ## Report files Prettier would change, without changing them
	cd $(BACKEND) && npm run format:check
	cd $(LANDING) && npm run format:check

# ─── iOS ──────────────────────────────────────────────────────────────────────
# These are NOT part of `check`. `check` mirrors the CI jobs, and CI has no macOS
# runner (see the trailing note in .github/workflows/ci.yml), so nothing below is
# enforced on a PR today. They are the same commands a CI job would run when a
# runner exists, so wiring one up is a copy of these recipes.
#
# Both tools are installed with:  brew install swiftlint swiftformat
# Each target skips rather than fails when the tool is missing, because the
# backend and landing site are developed on Linux too.

# Exits non-zero on an error-severity violation only. The config keeps errors at
# zero deliberately — force_cast, force_try, todo and the substring-host rule —
# so a failure here is a real regression, not accumulated debt. The 4,697
# warnings are measured debt with counts recorded in ios/.swiftlint.yml.
lint-ios: ## SwiftLint the iOS client (errors gate; warnings are reported)
	@command -v swiftlint >/dev/null 2>&1 \
	  && (cd $(IOS) && swiftlint lint --quiet) \
	  || echo "  swiftlint not found — skipping (brew install swiftlint)"

# Changed files only, for the same reason the Prettier `format` job is: a full pass
# reports 1,937 findings across 137 of the 220 files SwiftFormat reads, and rewrites
# `git blame` for more than half the client. The formatted share grows as files are
# touched. See ios/.swiftformat.
format-ios: ## Run SwiftFormat over Swift files changed against BASE_REF
	@command -v swiftformat >/dev/null 2>&1 || { \
	  echo "  swiftformat not found — skipping (brew install swiftformat)"; exit 0; }
	@$(MAKE) --no-print-directory ios-changed-swift > /tmp/plink-ios-changed.txt
	@if [ ! -s /tmp/plink-ios-changed.txt ]; then echo "  No Swift files changed against $(BASE_REF)"; exit 0; fi
	@cat /tmp/plink-ios-changed.txt
	@tr '\n' '\0' < /tmp/plink-ios-changed.txt | xargs -0 swiftformat --config $(IOS)/.swiftformat

format-check-ios: ## Report Swift files SwiftFormat would change, without changing them
	@command -v swiftformat >/dev/null 2>&1 || { \
	  echo "  swiftformat not found — skipping (brew install swiftformat)"; exit 0; }
	@$(MAKE) --no-print-directory ios-changed-swift > /tmp/plink-ios-changed.txt
	@if [ ! -s /tmp/plink-ios-changed.txt ]; then echo "  No Swift files changed against $(BASE_REF)"; exit 0; fi
	@tr '\n' '\0' < /tmp/plink-ios-changed.txt | xargs -0 swiftformat --config $(IOS)/.swiftformat --lint

ios: lint-ios format-check-ios ## Every iOS check (needs macOS + brew tools)

# ACMR: added, copied, modified, renamed — a deleted file has nothing to format.
# Written to a file by the callers rather than read into an array: `mapfile` needs
# bash 4 and macOS ships 3.2, so the array form would fail on the machine this
# target exists for. Prints nothing when there is no diff.
.PHONY: ios-changed-swift
ios-changed-swift:
	@git diff --name-only --diff-filter=ACMR "$(BASE_REF)...HEAD" 2>/dev/null \
	  | grep -E '^$(IOS)/.*\.swift$$' || true

backend: ## Typecheck and test the backend (Redis required for the integration suite)
	cd $(BACKEND) && npx prisma generate && npx tsc --noEmit && npx vitest run

landing: ## Typecheck and build the landing site
	cd $(LANDING) && npx tsc --noEmit && npm run build

android: ## Build and unit-test the Android client
	cd $(ANDROID) && ./gradlew assembleDebug testDebugUnitTest

test: ## Backend tests only
	cd $(BACKEND) && npx vitest run

# The integration suite refuses to run without REDIS_URL rather than skipping
# itself, so a green result here means it actually executed.
integration: ## Backend integration tests (requires REDIS_URL)
	cd $(BACKEND) && npm run test:integration

db-migrate: ## Apply pending migrations to DATABASE_URL
	cd $(BACKEND) && npx prisma migrate deploy

db-status: ## Show migration state without applying anything
	cd $(BACKEND) && npx prisma migrate status

# Plink.xcodeproj is generated and not tracked (ADR-0007). Run this after
# pulling changes to project.yml or after adding files outside Xcode.
xcode: ## Regenerate Plink.xcodeproj from project.yml
	cd $(IOS) && xcodegen generate

clean: ## Remove build output (not dependencies)
	rm -rf $(BACKEND)/dist $(LANDING)/.next $(IOS)/Plink.xcodeproj
	cd $(ANDROID) && ./gradlew clean
