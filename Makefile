#!/bin/bash

ARCH_MAP_x86_64 := amd64
ARCH_MAP_arm64 := arm64
ARCH_MAP_aarch64 := arm64

BUILDARCH := $(ARCH_MAP_$(shell uname -m))
BUILDOS := $(shell uname -s | tr '[:upper:]' '[:lower:]')

TARGETS := $(BUILDOS)/$(BUILDARCH)
DOCKER_BUILDX_PLATFORM := $(BUILDOS)/$(BUILDARCH)

OSM_HOME ?= $(abspath ../osm-edge)

egress-gateway:
	scripts/deploy-egress-gateway-demo.sh

udp-echo:
	scripts/deploy-udp-echo-demo.sh

ingress-nginx:
	scripts/deploy-ingress-nginx-demo.sh