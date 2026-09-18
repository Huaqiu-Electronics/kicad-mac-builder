#!/bin/bash

# Homebrew formulae needed to build KiCad.
#
# grpc is required by the HQ SDK in the KiCad fork: hq/sdk/cpp/CMakeLists.txt
# and hq/runtime/CMakeLists.txt both do `find_package( gRPC CONFIG REQUIRED )`,
# so without it KiCad's own configure step fails with
#   Could not find a package configuration file provided by "gRPC"
# It pulls abseil, c-ares, protobuf and re2 in automatically (protobuf is also
# listed explicitly because KiCad's own code uses protoc).
#
# FIXME: cmake 4.x is not compatible with kicad.  Need to figure out how to get cmake 3.x
# export BREW_DEPS=(glew bison opencascade glm boost harfbuzz cairo doxygen gettext wget libgit2 libtool autoconf automake cmake swig openssl unixodbc ninja grpc protobuf nng zstd libomp)
export BREW_DEPS=(glew bison opencascade glm boost harfbuzz cairo doxygen gettext wget libgit2 libtool autoconf automake swig openssl unixodbc ninja grpc protobuf nng zstd libomp)
