# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may
# not use this file except in compliance with the License. A copy of the
# License is located at
#
# 	http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.

# Set this to pass additional commandline flags to the go compiler, e.g. "make test EXTRAGOARGS=-v"
CARGO_CACHE_VOLUME_NAME?=firecracker-go-sdk--cargocache
DISABLE_ROOT_TESTS?=1
DOCKER_IMAGE_TAG?=latest
EXTRAGOARGS:=
FIRECRACKER_DIR=build/firecracker
arch=$(shell uname -m)
FIRECRACKER_TARGET?=$(arch)-unknown-linux-musl

FC_TEST_DATA_PATH?=testdata
FC_TEST_BIN_PATH:=$(FC_TEST_DATA_PATH)/bin
FIRECRACKER_BIN=$(FC_TEST_DATA_PATH)/firecracker-main
JAILER_BIN=$(FC_TEST_DATA_PATH)/jailer-main

UID = $(shell id -u)
GID = $(shell id -g)

# Version has to be in format of vx.x.x
firecracker_version=v1.18.0
FIRECRACKER_REVISION=eaf83bb718a559d324613d566eaf776b31a62340

# The below files are needed and can be downloaded from the internet
release_url=https://github.com/firecracker-microvm/firecracker/releases/download/$(firecracker_version)/firecracker-$(firecracker_version)-$(arch).tgz

testdata_objects = \
$(FC_TEST_DATA_PATH)/firecracker \
$(FC_TEST_BIN_PATH)/host-local \
$(FC_TEST_DATA_PATH)/jailer \
$(FC_TEST_BIN_PATH)/ltag \
$(FC_TEST_BIN_PATH)/ptp \
$(FC_TEST_DATA_PATH)/root-drive.img \
$(FC_TEST_DATA_PATH)/root-drive-with-ssh.img \
$(FC_TEST_DATA_PATH)/root-drive-ssh-key \
$(FC_TEST_BIN_PATH)/static \
$(FC_TEST_BIN_PATH)/tc-redirect-tap \
$(FC_TEST_DATA_PATH)/vmlinux

testdata_dir = testdata/firecracker.tgz testdata/firecracker_spec-$(firecracker_version).yaml testdata/LICENSE testdata/NOTICE testdata/THIRD-PARTY

# --location is needed to follow redirects
curl = curl --fail --location --retry 3

GO_VERSION = $(shell go version | cut -c 14- | cut -d' ' -f1 | cut -d'.' -f1,2)
ifeq ($(GO_VERSION), $(filter $(GO_VERSION),1.14 1.15))
    define install_go
		cd .hack; GO111MODULE=on GOBIN=$(abspath $(FC_TEST_BIN_PATH)) go get $(1)@$(2)
		cd .hack; GO111MODULE=on GOBIN=$(abspath $(FC_TEST_BIN_PATH)) go install $(1)
    endef
else
    define install_go
		GOBIN=$(abspath $(FC_TEST_BIN_PATH)) go install $(1)@$(2)
    endef
endif

all: build

test: all-tests

unit-tests: $(FC_TEST_DATA_PATH)/vmlinux $(FC_TEST_DATA_PATH)/root-drive.img
	DISABLE_ROOT_TESTS=$(DISABLE_ROOT_TESTS) go test -short ./... $(EXTRAGOARGS)

all-tests: $(testdata_objects)
	DISABLE_ROOT_TESTS=$(DISABLE_ROOT_TESTS) go test ./... $(EXTRAGOARGS)

generate build clean::
	go $@ $(EXTRAGOARGS)

clean::
	rm -fr build/

distclean: clean
	rm -rf $(testdata_objects)
	rm -f $(FC_TEST_DATA_PATH)/fc.stamp
	rm -rfv $(testdata_dir)
	docker volume rm -f $(CARGO_CACHE_VOLUME_NAME)

deps: $(testdata_objects)

$(FC_TEST_DATA_PATH)/vmlinux $(FC_TEST_DATA_PATH)/root-drive.img $(FC_TEST_DATA_PATH)/fc.stamp &: tools/prepare-testdata.sh
	FC_TEST_DATA_PATH=$(abspath $(FC_TEST_DATA_PATH)) bash tools/prepare-testdata.sh

$(FC_TEST_DATA_PATH)/firecracker $(FC_TEST_DATA_PATH)/jailer: $(FC_TEST_DATA_PATH)/fc.stamp

$(FC_TEST_DATA_PATH)/root-drive-ssh-key $(FC_TEST_DATA_PATH)/root-drive-with-ssh.img &: tools/prepare-testdata.sh
	FC_TEST_DATA_PATH=$(abspath $(FC_TEST_DATA_PATH)) bash tools/prepare-testdata.sh --ssh

$(FC_TEST_BIN_PATH)/ptp:
	$(call install_go,github.com/containernetworking/plugins/plugins/main/ptp,v1.9.1)

$(FC_TEST_BIN_PATH)/host-local:
	$(call install_go,github.com/containernetworking/plugins/plugins/ipam/host-local,v1.9.1)

$(FC_TEST_BIN_PATH)/static:
	$(call install_go,github.com/containernetworking/plugins/plugins/ipam/static,v1.9.1)

$(FC_TEST_BIN_PATH)/tc-redirect-tap:
	$(call install_go,github.com/awslabs/tc-redirect-tap/cmd/tc-redirect-tap,v0.0.0-20250516183331-34bf829e9a5c)

$(FC_TEST_BIN_PATH)/ltag:
	$(call install_go,github.com/kunalkushwaha/ltag,v0.2.5)

# test-images builds the exact supported Firecracker release from source.
.PHONY: test-images
test-images: $(FIRECRACKER_BIN) $(JAILER_BIN)

$(FIRECRACKER_DIR):
	git clone --depth 1 --branch $(firecracker_version) https://github.com/firecracker-microvm/firecracker.git $(FIRECRACKER_DIR)
	test "$$(git -C $(FIRECRACKER_DIR) rev-parse HEAD)" = "$(FIRECRACKER_REVISION)"

$(FIRECRACKER_BIN) $(JAILER_BIN): $(FIRECRACKER_DIR)
	$(FIRECRACKER_DIR)/tools/devtool -y build --release
	cp $(FIRECRACKER_DIR)/build/cargo_target/$(FIRECRACKER_TARGET)/release/firecracker $(FIRECRACKER_BIN)
	cp $(FIRECRACKER_DIR)/build/cargo_target/$(FIRECRACKER_TARGET)/release/jailer $(JAILER_BIN)

.PHONY: firecracker-clean
firecracker-clean:
	- $(FIRECRACKER_DIR)/tools/devtool distclean
	- rm $(FIRECRACKER_BIN) $(JAILER_BIN)

lint: deps
	test -z "$$(git ls-files '*.go' | xargs gofmt -s -l)"
	$(FC_TEST_DATA_PATH)/bin/ltag -check -v -t .headers -excludes "build testdata"

.PHONY: all generate clean distclean build test unit-tests all-tests check-kvm
