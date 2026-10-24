.PHONY: build test package check-package

ARCHIVE = dist/ipadecrypt-macos-$(shell uname -m).tar.gz
BUNDLES = fairdeckit_FairDecKit.bundle ZIPFoundation_ZIPFoundation.bundle

build:
	swift build -c release --product ipadecrypt
	@set -e; \
	bin_dir="$$(swift build -c release --show-bin-path)"; \
	mkdir -p dist; \
	cp "$$bin_dir/ipadecrypt" dist/; \
	for bundle in $(BUNDLES); do ditto "$$bin_dir/$$bundle" "dist/$$bundle"; done

test:
	swift test
	swift test --package-path Vendor/FairDecKit

package: build
	COPYFILE_DISABLE=1 tar -czf "$(ARCHIVE)" -C dist ipadecrypt $(BUNDLES)

check-package: package
	bash Tests/check-package.sh "$(ARCHIVE)"
