#!/bin/zsh

./build.py --arch=arm64 --release --target package-kicad-unified --kicad-ref release/9.0 \
           --symbols-ref 9.0.1 --footprints-ref 9.0.1 \
           --packages3d-ref 9.0.1 --templates-ref 9.0.1 \
           --docs-tarball-url https://gitlab.com/kicad/services/kicad-doc/-/archive/9.0.1/kicad-doc-9.0.1.tar.gz \
           --release-name kicad-9.0.1-macos-arm64-copilot