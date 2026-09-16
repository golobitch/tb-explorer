TB_VERSION   ?= 0.17.9
TB_BIN       := .bin/tigerbeetle
TB_DATA      ?= .tigerbeetle/0_0.tigerbeetle
TB_ADDR      ?= 127.0.0.1:3000
DERIVED      := build/DerivedData
XCB          := xcodebuild -project TBExplorer.xcodeproj -derivedDataPath $(DERIVED)

.PHONY: icon generate open build release test integration seed tb tb-format tb-start tb-up tb-stop tb-reset vendor clean

ICONSET := Sources/TBExplorer/Assets.xcassets/AppIcon.appiconset

# Render the app icon at 1024px and derive every size the asset catalog needs.
icon:
	swift scripts/render-icon.swift $(ICONSET)/icon_1024.png
	for s in 16 32 64 128 256 512; do sips -z $$s $$s $(ICONSET)/icon_1024.png --out $(ICONSET)/icon_$$s.png >/dev/null; done

generate:
	xcodegen generate --quiet

open: generate
	open TBExplorer.xcodeproj

build: generate
	$(XCB) -scheme TBExplorer -configuration Debug build | xcbeautify 2>/dev/null || $(XCB) -scheme TBExplorer -configuration Debug build -quiet

release: generate
	$(XCB) -scheme TBExplorer -configuration Release -arch arm64 -arch x86_64 ONLY_ACTIVE_ARCH=NO build -quiet
	@echo "App: $(DERIVED)/Build/Products/Release/TigerBeetle Explorer.app"

# Unit + integration tests. The scheme's Test pre-action starts and seeds the dev cluster.
test: generate
	$(XCB) -scheme TBExplorer test -quiet

integration: test

seed: generate
	$(XCB) -scheme tb-seed -configuration Debug build -quiet
	$(DERIVED)/Build/Products/Debug/tb-seed --addresses $(TB_ADDR)

$(TB_BIN):
	mkdir -p .bin
	curl -fsSL -o .bin/tb.zip https://github.com/tigerbeetle/tigerbeetle/releases/download/$(TB_VERSION)/tigerbeetle-universal-macos.zip
	cd .bin && unzip -o -q tb.zip && rm tb.zip
	$(TB_BIN) version

tb: $(TB_BIN)

tb-format: $(TB_BIN)
	mkdir -p $(dir $(TB_DATA))
	test -f $(TB_DATA) || $(TB_BIN) format --cluster=0 --replica=0 --replica-count=1 --development $(TB_DATA)

tb-start: tb-format
	$(TB_BIN) start --addresses=$(TB_ADDR) --development $(TB_DATA)

# Start (and seed, if new) the dev cluster in the background; no-op if already running.
tb-up:
	TB_ADDR=$(TB_ADDR) scripts/dev-cluster.sh

# Stop the replica holding this repo's data file, whatever address it listens on.
tb-stop:
	@pid=$$(lsof -t $(TB_DATA) 2>/dev/null); if [ -n "$$pid" ]; then kill $$pid && echo "stopped replica $$pid"; else echo "no replica running"; fi

tb-reset: tb-stop
	rm -rf .tigerbeetle

# Refresh the vendored C client from the tigerbeetle-go module of the same release.
vendor:
	rm -rf .bin/tbgo && mkdir -p .bin/tbgo
	curl -fsSL -o .bin/tbgo/mod.zip https://proxy.golang.org/github.com/tigerbeetle/tigerbeetle-go/@v/v$(TB_VERSION).zip
	cd .bin/tbgo && unzip -q mod.zip
	cp .bin/tbgo/github.com/tigerbeetle/tigerbeetle-go@v$(TB_VERSION)/native/tb_client.h Vendor/tigerbeetle/include/
	chmod 644 Vendor/tigerbeetle/include/tb_client.h
	# The Zig-built archives have members that are not 8-byte aligned; newer Apple
	# linkers skip such members entirely. Repack each slice with Apple's libtool.
	for arch in aarch64 x86_64; do \
	  mkdir -p .bin/tbgo/$$arch && cd .bin/tbgo/$$arch && \
	  ar -x ../github.com/tigerbeetle/tigerbeetle-go@v$(TB_VERSION)/native/libtb_client_$$arch-macos.a && \
	  chmod 644 *.o && libtool -static -o ../libtb_client_$$arch.a *.o && cd ../../.. || exit 1; \
	done
	rm -f Vendor/tigerbeetle/lib/libtb_client.a
	lipo -create .bin/tbgo/libtb_client_aarch64.a .bin/tbgo/libtb_client_x86_64.a \
	  -output Vendor/tigerbeetle/lib/libtb_client.a
	echo $(TB_VERSION) > Vendor/tigerbeetle/VERSION
	rm -rf .bin/tbgo

clean:
	rm -rf build TBExplorer.xcodeproj
