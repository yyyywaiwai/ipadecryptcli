#!/bin/bash
set -euo pipefail

archive="$1"
fixture="$PWD/Tests/ipadecryptTests/Fixtures/encrypted.zip"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

tar -xzf "$archive" -C "$work_dir"
cd "$work_dir"
test -x ipadecrypt
test -f fairdeckit_FairDecKit.bundle/Contents/Resources/transform_const_data.bin
test -d ZIPFoundation_ZIPFoundation.bundle
./ipadecrypt --help
printf '\000\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017' > credential.bin

for mode in lowmem fast; do
    cp "$fixture" "$mode.ipa"
    ./ipadecrypt "$mode.ipa" -c credential.bin --mode "$mode"
    cmp "$fixture" "$mode.ipa"
    ditto -x -k "$mode.decrypted.ipa" "$mode"
    hash="$(shasum -a 256 "$mode/Payload/Sample.app/Sample")"
    test "${hash%% *}" = fe99157964b099981db8b68e7277c1d65dde7967ce6e45786b3f32e60410bc3d
    test "$(cat "$mode/Payload/Sample.app/resource.txt")" = 'resource preserved'
done
