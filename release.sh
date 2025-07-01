#!/bin/zsh

TAG=${1:-9.0.2}      # Use first argument, or default to 9.0.2
ARCH=${2:-arm64}     # Use second argument, or default to arm64

export WX_SKIP_DOXYGEN_VERSION_CHECK=1  

./build.py --arch=$ARCH --release --target package-kicad-unified --kicad-ref release/9.0 \
           --symbols-ref $TAG --footprints-ref $TAG \
           --packages3d-ref $TAG --templates-ref $TAG \
           --docs-tarball-url https://gitlab.com/kicad/services/kicad-doc/-/archive/$TAG/kicad-doc-$TAG.tar.gz \
           --release-name huaqiu-$TAG-macos-$ARCH