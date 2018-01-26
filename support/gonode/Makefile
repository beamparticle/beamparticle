# copyright (c) 2017 Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>

.DEFAULT_GOAL := release

MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
MAKEFILE_FOLDER := $(dir $(MAKEFILE_PATH))

release: deps
	go build gonode.go

clean:
	rm -rf gonode

deps:
	go get "github.com/halturin/ergonode"

.PHONY: help release clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
