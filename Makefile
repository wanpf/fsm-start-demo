#!/bin/bash

CTR_REGISTRY ?= flomesh
CTR_TAG      ?= latest
CTR_REPO     ?= https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/main

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

switch-osm-edge-image-registry-flomesh:
	scripts/switch-osm-edge-image-registry.sh flomesh

switch-osm-edge-image-registry-cybwan:
	scripts/switch-osm-edge-image-registry.sh cybwan

switch-osm-edge-image-registry-local:
	scripts/switch-osm-edge-image-registry.sh localhost:5000/flomesh

switch-osm-edge-image-registry:
	scripts/switch-osm-edge-image-registry.sh $(CTR_REGISTRY)

switch-osm-edge-image-tag:
	scripts/switch-osm-edge-image-tag.sh $(CTR_TAG)

switch-osm-edge-demo-repo:
	scripts/switch-osm-edge-demo-repo.sh $(CTR_REPO)

switch-osm-edge-demo-repo-local:
	scripts/switch-osm-edge-demo-repo.sh .