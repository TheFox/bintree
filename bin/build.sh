#!/usr/bin/env bash

set -x

for target in aarch64-macos x86_64-linux ; do
    echo "-> target: ${target}"
    zig build --verbose --summary all --release=small -Dtarget=${target}
done
