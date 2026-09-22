.PHONY: build run test dmg design-names
build:
	@scripts/bundle.sh debug
run: build
	@open build/Sift.app
test:
	@swift test

# The release disk image (D-247). CI runs this on a tag and attaches the result;
# locally it is how to see what a reader downloads. Pass VERSION= to match a tag,
# or leave it and take the one in Info.plist.
dmg:
	@scripts/dmg.sh $(VERSION)

# Author-only. The design document is local-only, so the names it declares ship
# as a fixture and the reasoning does not; on a clone there is no document to
# read and the fixture is the contract. Run this after editing the document; the
# suite fails until you do.
design-names:
	@SIFT_REFRESH_DESIGN_NAMES=1 swift test --filter theNameFixtureMatchesTheDesignDocument >/dev/null
	@echo "Tests/SiftTests/Fixtures/design-names.txt: $$(wc -l < Tests/SiftTests/Fixtures/design-names.txt | tr -d ' ') names"
