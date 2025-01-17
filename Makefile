#!/usr/bin/make -f

SHELL := /bin/sh
.SHELLFLAGS := -euc

DOCKER := $(shell command -v docker 2>/dev/null)
GIT := $(shell command -v git 2>/dev/null)

DISTDIR := ./dist
DOCKERFILE := ./Dockerfile

IMAGE_REGISTRY := docker.io
IMAGE_NAMESPACE := hectorm
IMAGE_PROJECT := wine
IMAGE_NAME := $(IMAGE_REGISTRY)/$(IMAGE_NAMESPACE)/$(IMAGE_PROJECT)
IMAGE_GIT_TAG := $(shell '$(GIT)' tag -l --contains HEAD 2>/dev/null)
IMAGE_GIT_SHA := $(shell '$(GIT)' rev-parse HEAD 2>/dev/null)
IMAGE_VERSION := $(if $(IMAGE_GIT_TAG),$(IMAGE_GIT_TAG),$(if $(IMAGE_GIT_SHA),$(IMAGE_GIT_SHA),nil))

IMAGE_BUILD_OPTS :=

IMAGE_TARBALL := $(DISTDIR)/$(IMAGE_PROJECT).tzst

export DOCKER_BUILDKIT := 1
export BUILDKIT_PROGRESS := plain

##################################################
## "all" target
##################################################

.PHONY: all
all: save-image

##################################################
## "build-*" targets
##################################################

.PHONY: build-image
build-image:
	'$(DOCKER)' build $(IMAGE_BUILD_OPTS) \
		--tag '$(IMAGE_NAME):$(IMAGE_VERSION)' \
		--tag '$(IMAGE_NAME):latest' \
		--file '$(DOCKERFILE)' ./

##################################################
## "save-*" targets
##################################################

define save_image
	'$(DOCKER)' save '$(1)' | zstd -T0 > '$(2)'
endef

.PHONY: save-image
save-image: $(IMAGE_TARBALL)

$(IMAGE_TARBALL): build-image
	mkdir -p '$(DISTDIR)'
	$(call save_image,$(IMAGE_NAME):$(IMAGE_VERSION),$@)

##################################################
## "load-*" targets
##################################################

define load_image
	zstd -dc '$(1)' | '$(DOCKER)' load
endef

define tag_image
	'$(DOCKER)' tag '$(1)' '$(2)'
endef

.PHONY: load-image
load-image:
	$(call load_image,$(IMAGE_TARBALL))
	$(call tag_image,$(IMAGE_NAME):$(IMAGE_VERSION),$(IMAGE_NAME):latest)

##################################################
## "push-*" targets
##################################################

define push_image
	'$(DOCKER)' push '$(1)'
endef

.PHONY: push-image
push-image:
	$(call push_image,$(IMAGE_NAME):$(IMAGE_VERSION))
	$(call push_image,$(IMAGE_NAME):latest)

##################################################
## "version" target
##################################################

.PHONY: version
version:
	@LATEST_IMAGE_VERSION=$$('$(GIT)' describe --abbrev=0 2>/dev/null || printf 'v0'); \
	if printf '%s' "$${LATEST_IMAGE_VERSION:?}" | grep -q '^v[0-9]\{1,\}$$'; then \
		NEW_IMAGE_VERSION=$$(awk -v v="$${LATEST_IMAGE_VERSION:?}" 'BEGIN {printf("v%.0f", substr(v,2)+1)}'); \
		'$(GIT)' commit --allow-empty -m "$${NEW_IMAGE_VERSION:?}"; \
		'$(GIT)' tag -a "$${NEW_IMAGE_VERSION:?}" -m "$${NEW_IMAGE_VERSION:?}"; \
	else \
		>&2 printf 'Malformed version string: %s\n' "$${LATEST_IMAGE_VERSION:?}"; \
		exit 1; \
	fi

##################################################
## "clean" target
##################################################

.PHONY: clean
clean:
	rm -f '$(IMAGE_TARBALL)'
	if [ -d '$(DISTDIR)' ] && [ -z "$$(ls -A '$(DISTDIR)')" ]; then rmdir '$(DISTDIR)'; fi
