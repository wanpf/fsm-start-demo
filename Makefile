#!/bin/bash

CTR_REGISTRY ?= flomesh
CTR_TAG      ?= latest
CTR_REPO     ?= https://raw.githubusercontent.com/cybwan/fsm-start-demo/main

ARCH_MAP_x86_64 := amd64
ARCH_MAP_arm64 := arm64
ARCH_MAP_aarch64 := arm64

BUILDARCH := $(ARCH_MAP_$(shell uname -m))
BUILDOS := $(shell uname -s | tr '[:upper:]' '[:lower:]')

TARGETS := $(BUILDOS)/$(BUILDARCH)
DOCKER_BUILDX_PLATFORM := $(BUILDOS)/$(BUILDARCH)

FSM_HOME ?= $(abspath ../fsm)

egress-gateway:
	scripts/deploy-egress-gateway-demo.sh

udp-echo:
	scripts/deploy-udp-echo-demo.sh

ingress-nginx:
	scripts/deploy-ingress-nginx-demo.sh

switch-fsm-image-registry-flomesh:
	scripts/switch-fsm-image-registry.sh flomesh

switch-fsm-image-registry-cybwan:
	scripts/switch-fsm-image-registry.sh cybwan

switch-fsm-image-registry-local:
	scripts/switch-fsm-image-registry.sh localhost:5000/flomesh

switch-fsm-image-registry:
	scripts/switch-fsm-image-registry.sh $(CTR_REGISTRY)

switch-fsm-image-tag:
	scripts/switch-fsm-image-tag.sh $(CTR_TAG)

switch-fsm-demo-repo:
	scripts/switch-fsm-demo-repo.sh $(CTR_REPO)

switch-fsm-demo-repo-local:
	scripts/switch-fsm-demo-repo.sh .