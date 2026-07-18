ZIG ?= zig
CPU ?= baseline

.PHONY: build test smoke skills docker helm-lint

build:
	$(ZIG) build -Doptimize=ReleaseSafe -Dcpu=$(CPU)

test:
	$(ZIG) build test -Dcpu=$(CPU)

skills:
	$(ZIG) build skills -Dcpu=$(CPU)

smoke: build
	./scripts/smoke.sh

docker:
	docker build -t deepiri-bedd:local .

helm-lint:
	helm lint deploy/helm/bedd

.PHONY: bench
bench: build
	N=200 ./scripts/bench-strike.sh

.PHONY: doctor
doctor: build
	./zig-out/bin/bedd doctor

.PHONY: serve-dry
serve-dry: build
	BEDD_DRY_RUN=1 BEDD_TINDER=tinder.example.json ./zig-out/bin/bedd serve
