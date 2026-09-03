PYTHON ?= python3
MACOS_DEVELOPER_DIR ?= /Library/Developer/CommandLineTools

.PHONY: verify release-candidate macos-test macos-build site-test package-macos

verify: macos-test macos-build site-test

release-candidate: verify

macos-test:
	cd macos && DEVELOPER_DIR="$(MACOS_DEVELOPER_DIR)" swift run PaceBackVerification

macos-build:
	cd macos && DEVELOPER_DIR="$(MACOS_DEVELOPER_DIR)" swift build --product PaceBack

site-test:
	$(PYTHON) site/scripts/check_site.py
	node --check site/app.js

package-macos:
	MACOS_DEVELOPER_DIR="$(MACOS_DEVELOPER_DIR)" scripts/package_macos.sh
