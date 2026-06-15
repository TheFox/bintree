#!/usr/bin/env bash

for target in aarch64-macos x86_64-linux ; do
    echo "-> target: ${target}"
    if ! zig build install --verbose --summary all --release -Dtarget=${target} ; then
        echo 'ERROR: target build failed'
        exit 1
    fi
done
