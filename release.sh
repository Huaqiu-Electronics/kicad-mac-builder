#!/bin/zsh

./build.py --arch=arm64 --release --target package-kicad-unified --kicad-ref release/9.0 \
           --symbols-ref 9.0.2 --footprints-ref 9.0.2 \
           --packages3d-ref 9.0.2 --templates-ref 9.0.2 \
           --docs-tarball-url https://gitlab.com/kicad/services/kicad-doc/-/archive/9.0.2/kicad-doc-9.0.2.tar.gz \
           --release-name kicad-huaqiu-9.0.2-macos-arm64