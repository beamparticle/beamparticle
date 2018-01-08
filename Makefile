# copyright (c) 2017 Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>

.DEFAULT_GOAL := help

COMPONENT=beamparticle

VER=$(shell make get-version)

MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
PROD_TAR_PATH = $(MAKEFILE_PATH)/_build/prod/rel/$(COMPONENT)/$(COMPONENT)-$(VER).tar.gz

COMMIT_INFO=$(shell make get-commit-info)
COMMIT=$(shell git show --format='%h' -s)
LAST_UPDATE=$(shell git show --format='%cD' -s)
COMMIT_TITLE=$(shell git show --format='%s' -s | sed -e 's/"/ /g')

clean:
	./rebar3 clean
	make -C packaging/debian clean

get-version-json: ## Get version information as json
	@echo '{"version":"$(VER)","commit":"$(COMMIT)","last_update":"$(LAST_UPDATE)","commit_title":"$(COMMIT_TITLE)"}'

#@echo '{"version":"$(VER)",$(COMMIT_INFO)}'

get-commit-info: ## Get last commit, last update date and commit title
	@git show --format='"commit":"%h","last_update":"%cD","commit_title":"%s"' -s

get-version: ## Get project version or vsn
	@grep vsn src/beamparticle.app.src | cut -f2 -d'"'

support/pynode/Pyrlang:
	git submodule init \
		&& git submodule update

pynode: support/pynode/Pyrlang support/pynode/pynode.py
	./build_pynode.sh

release:
	./rebar3 release

gen-prod-tar:
	./rebar3 as prod tar

deb-package: clean gen-prod-tar
	make -C packaging/debian VERSION=$(VER) COMPONENT=$(COMPONENT) package

deb-package-upgrade: gen-prod-tar
	make -C packaging/debian VERSION=$(VER) COMPONENT=$(COMPONENT) package-upgrade

.PHONY: help deb-package deb-package-upgrade gen-prod-tar

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
