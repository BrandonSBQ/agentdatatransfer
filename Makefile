CMAKE_PREFIX_PATH ?= /opt/homebrew;/opt/homebrew/opt/libarchive
BUILD_DIR ?= build
JOBS ?= 4
ENV_FILE ?= .env

.PHONY: all configure build run clean

all: build

configure:
	cmake -S . -B $(BUILD_DIR) -DCMAKE_PREFIX_PATH='$(CMAKE_PREFIX_PATH)'

build: configure
	cmake --build $(BUILD_DIR) -j$(JOBS)

run: build
	set -a && [ -f $(ENV_FILE) ] && . ./$(ENV_FILE) && set +a && ./$(BUILD_DIR)/company_oss_file_service

clean:
	rm -rf $(BUILD_DIR)
