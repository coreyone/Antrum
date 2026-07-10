SHELL := /bin/bash

.PHONY: generate build test run lint doctor secret-scan public-check

generate:
	bash scripts/antrum generate

build:
	bash scripts/antrum build

test:
	bash scripts/antrum test

run:
	bash scripts/antrum run

lint:
	bash scripts/antrum lint

doctor:
	bash scripts/antrum doctor

secret-scan:
	bash scripts/antrum secret-scan

public-check:
	bash scripts/antrum public-check
