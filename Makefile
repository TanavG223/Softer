PYTHON ?= python3
ENGINE_PYTHON ?= .venv/bin/python
IOS_PROJECT ?= ios/PaceBackiOS.xcodeproj
IOS_SCHEME ?= PaceBackiOS
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=latest
IOS_DERIVED_DATA ?= ios/.derivedData-make

.PHONY: verify benchmark-validate benchmark-test benchmark-lint reranker-contract engine-test engine-lint macos-test macos-build ios-test ios-build site-test package-macos

verify: benchmark-validate benchmark-test benchmark-lint reranker-contract engine-test engine-lint macos-test macos-build ios-test ios-build site-test

benchmark-validate:
	$(PYTHON) benchmark/build_benchmark.py --check
	$(PYTHON) benchmark/validate_benchmark.py

benchmark-test:
	$(ENGINE_PYTHON) -m unittest discover -s benchmark/tests -p 'test_*.py' -v

benchmark-lint:
	$(ENGINE_PYTHON) -m ruff check benchmark

reranker-contract:
	$(PYTHON) benchmark/train_reranker.py \
		--judgments benchmark/reranker_dev_judgments.example.jsonl \
		--validate-only

engine-test:
	PYTHONPATH=engine/src $(ENGINE_PYTHON) -m pytest -q engine/tests

engine-lint:
	$(ENGINE_PYTHON) -m ruff check engine/src engine/tests

macos-test:
	cd macos && swift test

macos-build:
	cd macos && swift build

ios-test:
	xcodebuild \
		-project "$(IOS_PROJECT)" \
		-scheme "$(IOS_SCHEME)" \
		-configuration Debug \
		-destination "$(IOS_DESTINATION)" \
		-derivedDataPath "$(IOS_DERIVED_DATA)" \
		test

ios-build:
	xcodebuild \
		-project "$(IOS_PROJECT)" \
		-scheme "$(IOS_SCHEME)" \
		-configuration Release \
		-sdk iphonesimulator \
		-destination "generic/platform=iOS Simulator" \
		-derivedDataPath "$(IOS_DERIVED_DATA)" \
		CODE_SIGNING_ALLOWED=NO \
		build

site-test:
	$(PYTHON) site/scripts/check_site.py
	node --check site/app.js

package-macos:
	ENGINE_PYTHON=$(ENGINE_PYTHON) scripts/package_macos.sh
