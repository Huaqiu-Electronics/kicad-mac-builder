#!/bin/zsh

# Run ci/src/get-wrangle-bundle.sh to setup virtualenv

if [ ! -e virtualenv/bin/wrangle-bundle ]; then
    # Run the script
    ./ci/src/get-wrangle-bundle.sh
fi

source virtualenv/bin/activate

# Set default values for tag and arch, similar to release.sh
TAG=${1:-9.0.2}
ARCH=${2:-arm64}

export WX_SKIP_DOXYGEN_VERSION_CHECK=1

# Set refs and release name, similar to release.sh
export KICAD_REF="release/9.0"
export SYMBOLS_REF="$TAG"
export FOOTPRINTS_REF="$TAG"
export PACKAGES3D_REF="$TAG"
export TEMPLATES_REF="$TAG"
export DOCS_TARBALL_URL="https://gitlab.com/kicad/services/kicad-doc/-/archive/$TAG/kicad-doc-$TAG.tar.gz"
export RELEASE_NAME="huaqiu-$TAG-macos-universal"

# Optionally, pass extra version or release args if needed
export EXTRA_VERSION=""
export RELEASE_ARG="--release"

# Call the universal build script
./ci/src/make-universal-build-with-refs.sh