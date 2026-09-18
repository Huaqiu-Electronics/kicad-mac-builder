include(ExternalProject)

# ---------------------------------------------------------------------------
# edge-headless — the Huaqiu HQ Edge / DSH runtime bundled into KiCad.app.
#
# Scope (task kicad-dsh-mac-package.md):
#   * Apple Silicon (arm64) KiCad bundles a self-contained arm64
#     edge-headless runtime.  Nothing is downloaded at runtime, nothing is
#     installed globally, and `dsh` is NOT added to PATH.
#   * Intel (x86_64) KiCad is unchanged: no edge-headless is bundled and
#     HQ_EDGE_LAUNCHER never starts, so the Copilot panel keeps using the
#     existing online Copilot (https://chat.eda.cn/).
#
# The release is PINNED (version + asset + SHA256).  There is no "latest", no
# npm install and no fallback to a developer checkout: if the artifact cannot
# be fetched, hashed or extracted, the build fails.
#
# Where it lands:
#   KiCad.app/Contents/Resources/edge-headless/
#       bin/node                  bundled Node (arm64)
#       bin/hq-edge-server.cjs    hq-edge entrypoint
#       bin/dsh, bin/dsh-cli.cjs  DSH CLI launcher (bundle-internal only)
#       config/, dsh/, dsh-plugins/, node_modules/, public/
#
# Contents/Resources is used (rather than a bespoke Contents/edge-headless)
# because it is the canonical macOS location for material shipped inside the
# bundle, it already matches KiCad's own convention of putting bundled
# third-party material there (Contents/Resources/Licenses), and
# bin/apple.py already walks Contents/Resources when collecting code to sign.
#
# Ordering: install-edge-headless-into-app runs after KiCad's `install` and
# before `sign-app`, so the application signature covers the bundled
# executables (see the DEPENDEES list of sign-app in kicad.cmake).
# ---------------------------------------------------------------------------

# --- Pinned release -------------------------------------------------------
# The pin lives in <repo>/build-config.json and is read below.  Bump it with
#     kicad-mac-builder/bin/pin-edge-headless.py --version <tag> --local <zip>
# version, asset and SHA256 MUST move together — there is no "latest", so a
# stale pair always fails the build rather than shipping the wrong runtime.
#
# Every value can still be overridden per build
# (build.py --edge-headless-version / --edge-headless-sha256 /
#  --edge-headless-url / --no-edge-headless); those flags win over the file.

set( EDGE_HEADLESS_CONFIG_FILE "${CMAKE_CURRENT_LIST_DIR}/../build-config.json"
     CACHE FILEPATH "JSON file holding the pinned edge-headless release." )

set( EDGE_HEADLESS_VERSION  "" CACHE STRING "Pinned edge-headless release tag (from EDGE_HEADLESS_CONFIG_FILE)." )
set( EDGE_HEADLESS_ASSET    "" CACHE STRING "Pinned edge-headless release asset for macOS arm64 (from EDGE_HEADLESS_CONFIG_FILE)." )
set( EDGE_HEADLESS_SHA256   "" CACHE STRING "SHA256 of EDGE_HEADLESS_ASSET (from EDGE_HEADLESS_CONFIG_FILE)." )
set( EDGE_HEADLESS_URL      "" CACHE STRING "Override the edge-headless artifact location (URL, file:// URL or local path)." )
set( EDGE_HEADLESS_REPO_URL "" CACHE STRING "Base URL for edge-headless release downloads (from EDGE_HEADLESS_CONFIG_FILE)." )
set( EDGE_HEADLESS_ENABLE   ON CACHE BOOL "Bundle edge-headless into KiCad.app (Apple Silicon arm64 builds only)." )

if( EDGE_HEADLESS_CONFIG_FILE STREQUAL "" OR NOT EXISTS "${EDGE_HEADLESS_CONFIG_FILE}" )
    message( FATAL_ERROR
             "Edge-headless pin file not found: '${EDGE_HEADLESS_CONFIG_FILE}'.\n"
             "This file pins the bundled hq-edge runtime (version + SHA256); without it the\n"
             "build cannot be reproduced. Pass -DEDGE_HEADLESS_CONFIG_FILE=<path>, or see\n"
             "docs/edge-headless-integration.md." )
endif()

file( READ "${EDGE_HEADLESS_CONFIG_FILE}" _eh_config_json )

# Fail with a useful message on a truncated/hand-edited pin file, rather than
# reporting an "incomplete pin" later on.
string( JSON _eh_section_type ERROR_VARIABLE _eh_section_err TYPE "${_eh_config_json}" edgeHeadless )

if( _eh_section_err )
    message( FATAL_ERROR
             "'${EDGE_HEADLESS_CONFIG_FILE}' could not be parsed, or it has no "
             "top-level \"edgeHeadless\" object: ${_eh_section_err}" )
endif()

macro( _eh_config_value _out _key )
    set( ${_out} "" )
    string( JSON _eh_v ERROR_VARIABLE _eh_err GET "${_eh_config_json}" edgeHeadless ${_key} )
    if( NOT _eh_err )
        set( ${_out} "${_eh_v}" )
    endif()
endmacro()

_eh_config_value( _eh_json_enable   enable )
_eh_config_value( _eh_json_version  version )
_eh_config_value( _eh_json_asset    asset )
_eh_config_value( _eh_json_sha256   sha256 )
_eh_config_value( _eh_json_repo_url repoUrl )

if( EDGE_HEADLESS_ENABLE AND _eh_json_enable STREQUAL "OFF" )
    set( EDGE_HEADLESS_ENABLE OFF )
endif()

foreach( _eh_pair IN ITEMS "VERSION;_eh_json_version"
                           "ASSET;_eh_json_asset"
                           "SHA256;_eh_json_sha256"
                           "REPO_URL;_eh_json_repo_url" )
    list( GET _eh_pair 0 _eh_var )
    list( GET _eh_pair 1 _eh_json_var )

    if( EDGE_HEADLESS_${_eh_var} STREQUAL "" AND NOT ${_eh_json_var} STREQUAL "" )
        set( EDGE_HEADLESS_${_eh_var} "${${_eh_json_var}}" )
    endif()
endforeach()

# --- Architecture ---------------------------------------------------------
# build.py always passes --arch on Apple Silicon
# (-DCMAKE_APPLE_SILICON_PROCESSOR=<arch>).  On an Intel host --arch is
# optional, so fall back to the host processor, which is x86_64 there.
if( NOT DEFINED EDGE_HEADLESS_ARCH OR EDGE_HEADLESS_ARCH STREQUAL "" )
    if( DEFINED CMAKE_APPLE_SILICON_PROCESSOR AND NOT CMAKE_APPLE_SILICON_PROCESSOR STREQUAL "" )
        set( EDGE_HEADLESS_ARCH "${CMAKE_APPLE_SILICON_PROCESSOR}" )
    else()
        set( EDGE_HEADLESS_ARCH "${CMAKE_HOST_SYSTEM_PROCESSOR}" )
    endif()
endif()

if( APPLE AND EDGE_HEADLESS_ENABLE AND EDGE_HEADLESS_ARCH STREQUAL "arm64" )
    set( HQ_EDGE_HEADLESS_BUNDLE ON )
else()
    set( HQ_EDGE_HEADLESS_BUNDLE OFF )
endif()

set( EDGE_HEADLESS_INSTALL_DIR ${CMAKE_BINARY_DIR}/edge-headless-dest )
set( EDGE_HEADLESS_APP_REL_DIR "Contents/Resources/edge-headless" )

# Half of a (version, SHA256) pair identifies nothing useful — catch the case
# where only one side was overridden.
if( NOT _eh_json_version STREQUAL "" AND NOT _eh_json_sha256 STREQUAL "" )
    if( EDGE_HEADLESS_VERSION STREQUAL _eh_json_version
        AND NOT EDGE_HEADLESS_SHA256 STREQUAL _eh_json_sha256 )
        message( WARNING
                 "EDGE_HEADLESS_SHA256 was overridden for the pinned version "
                 "${EDGE_HEADLESS_VERSION}; version and SHA256 belong to one artifact, "
                 "so bump them together in ${EDGE_HEADLESS_CONFIG_FILE}." )
    elseif( NOT EDGE_HEADLESS_VERSION STREQUAL _eh_json_version
            AND EDGE_HEADLESS_SHA256 STREQUAL _eh_json_sha256 )
        message( WARNING
                 "EDGE_HEADLESS_VERSION overridden to ${EDGE_HEADLESS_VERSION} but the "
                 "SHA256 is still the pin for ${_eh_json_version} from "
                 "${EDGE_HEADLESS_CONFIG_FILE}; pass -DEDGE_HEADLESS_SHA256=... too "
                 "(or update the pin with kicad-mac-builder/bin/pin-edge-headless.py)." )
    endif()
endif()

message( STATUS "edge-headless: arch=${EDGE_HEADLESS_ARCH} bundled=${HQ_EDGE_HEADLESS_BUNDLE}"
                " version=${EDGE_HEADLESS_VERSION} asset=${EDGE_HEADLESS_ASSET}"
                " pin=${EDGE_HEADLESS_CONFIG_FILE}" )

if( HQ_EDGE_HEADLESS_BUNDLE )

    # Fail at configure time rather than downloading something unspecified.
    set( _eh_missing "" )
    foreach( _eh_field IN ITEMS VERSION ASSET SHA256 )
        if( EDGE_HEADLESS_${_eh_field} STREQUAL "" )
            list( APPEND _eh_missing ${_eh_field} )
        endif()
    endforeach()

    if( _eh_missing )
        string( REPLACE ";" ", " _eh_missing_list "${_eh_missing}" )
        message( FATAL_ERROR
                 "edge-headless pin is incomplete: ${_eh_missing_list} is empty.\n"
                 "Set it in '${EDGE_HEADLESS_CONFIG_FILE}' (see docs/edge-headless-integration.md)"
                 " or override it with -DEDGE_HEADLESS_<field>=... ." )
    endif()

    # CMake's regex engine has no {n} repetition, so check length + charset.
    string( LENGTH "${EDGE_HEADLESS_SHA256}" _eh_sha_len )
    string( REGEX MATCHALL "[^0-9a-fA-F]" _eh_sha_bad "${EDGE_HEADLESS_SHA256}" )

    if( NOT _eh_sha_len EQUAL 64 OR _eh_sha_bad )
        message( FATAL_ERROR
                 "EDGE_HEADLESS_SHA256 ('${EDGE_HEADLESS_SHA256}') is ${_eh_sha_len} characters "
                 "and/or contains non-hex characters; expected a 64 character SHA256 digest." )
    endif()

    ExternalProject_Add(
        edge-headless
        PREFIX  edge-headless
        DOWNLOAD_COMMAND ""
        UPDATE_COMMAND   ""
        PATCH_COMMAND    ""
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env
                          "EDGE_HEADLESS_VERSION=${EDGE_HEADLESS_VERSION}"
                          "EDGE_HEADLESS_ASSET=${EDGE_HEADLESS_ASSET}"
                          "EDGE_HEADLESS_SHA256=${EDGE_HEADLESS_SHA256}"
                          "EDGE_HEADLESS_URL=${EDGE_HEADLESS_URL}"
                          "EDGE_HEADLESS_REPO_URL=${EDGE_HEADLESS_REPO_URL}"
                          "EDGE_HEADLESS_ARCH=${EDGE_HEADLESS_ARCH}"
                          "EDGE_HEADLESS_DOWNLOAD_DIR=${CMAKE_BINARY_DIR}/edge-headless"
                          "EDGE_HEADLESS_DEST=${EDGE_HEADLESS_INSTALL_DIR}"
                          ${BIN_DIR}/fetch-edge-headless.sh
        BUILD_COMMAND ""
        INSTALL_COMMAND ""
    )

    # The `kicad` ExternalProject must not start staging until the runtime
    # has been fetched and validated.
    add_dependencies( kicad edge-headless )

endif()

# ---------------------------------------------------------------------------
# install-edge-headless-into-app
#
# Defined unconditionally (as a no-op on x86_64) so that the DEPENDEES list of
# `sign-app` in kicad.cmake can reference it without a per-architecture
# branch: the stamp file is always produced, signing never races the copy.
# ---------------------------------------------------------------------------
if( HQ_EDGE_HEADLESS_BUNDLE )

    ExternalProject_Add_Step(
        kicad
        install-edge-headless-into-app
        COMMENT "Installing edge-headless ${EDGE_HEADLESS_VERSION} into KiCad.app"
        DEPENDEES install
        COMMAND rm -rf ${KICAD_INSTALL_DIR}/KiCad.app/${EDGE_HEADLESS_APP_REL_DIR}
        COMMAND mkdir -p ${KICAD_INSTALL_DIR}/KiCad.app/${EDGE_HEADLESS_APP_REL_DIR}
        COMMAND rsync -al ${EDGE_HEADLESS_INSTALL_DIR}/ ${KICAD_INSTALL_DIR}/KiCad.app/${EDGE_HEADLESS_APP_REL_DIR}/
        COMMAND ${CMAKE_COMMAND} -E env
                "EDGE_HEADLESS_VERSION=${EDGE_HEADLESS_VERSION}"
                "EDGE_HEADLESS_ARCH=${EDGE_HEADLESS_ARCH}"
                ${BIN_DIR}/verify-edge-headless.sh ${KICAD_INSTALL_DIR}/KiCad.app
    )
    ExternalProject_Add_StepTargets( kicad install-edge-headless-into-app )

else()

    ExternalProject_Add_Step(
        kicad
        install-edge-headless-into-app
        COMMENT "Skipping edge-headless (not an Apple Silicon arm64 build)"
        DEPENDEES install
        COMMAND ${CMAKE_COMMAND} -E echo "edge-headless not bundled for ${EDGE_HEADLESS_ARCH}"
    )
    ExternalProject_Add_StepTargets( kicad install-edge-headless-into-app )

endif()
