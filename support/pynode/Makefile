# copyright (c) 2017 Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>

.DEFAULT_GOAL := release

MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
MAKEFILE_FOLDER := $(dir $(MAKEFILE_PATH))
ZIP_PATH = $(MAKEFILE_FOLDER)Pyrlang.zip

release:
	cd Pyrlang \
		&& python3 -m compileall Pyrlang \
		&& zip -r ../Pyrlang.zip Pyrlang

clean:
	rm -rf $(ZIP_PATH)


.PHONY: help release clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
