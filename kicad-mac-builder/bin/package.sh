#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

DEVICE=""

cleanup() {
    echo "Cleaning up mounts..."

    if [ -n "${DEVICE:-}" ]; then
        hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true
    fi

    if [ -n "${MOUNTPOINT:-}" ] && [ -d "${MOUNTPOINT}" ]; then
        rm -rf "${MOUNTPOINT}" || true
    fi
}

trap cleanup EXIT

attach_dmg() {
    echo "Attaching template DMG..."

    ATTACH_OUTPUT=$(hdiutil attach "${TEMPLATE}" -noautoopen -mountpoint "${MOUNTPOINT}")

    echo "$ATTACH_OUTPUT"

    DEVICE=$(echo "$ATTACH_OUTPUT" | grep "^/dev/" | head -n1 | awk '{print $1}')

    if [ -z "$DEVICE" ]; then
        echo "Failed to determine attached device"
        exit 1
    fi

    echo "Mounted device: $DEVICE"
}

detach_dmg() {
    echo "Detaching $DEVICE"

    for i in {1..10}; do
        if hdiutil detach "$DEVICE" >/dev/null 2>&1; then
            DEVICE=""
            return
        fi

        echo "Retry detach ($i)..."
        sleep 3
    done

    echo "Force detaching..."
    hdiutil detach -force "$DEVICE" || true
    DEVICE=""
}

setup_dmg() {

    rm -rf "${MOUNTPOINT}"
    mkdir -p "${MOUNTPOINT}"

    echo "Extracting DMG template..."

    rm -f "${TEMPLATE}"
    tar xf "${PACKAGING_DIR}/${TEMPLATE}.tar.bz2"

    if [ ! -f "${TEMPLATE}" ]; then
        echo "Template extraction failed"
        exit 1
    fi

    echo "Resizing template..."

    if ! hdiutil resize -sectors "${DMG_SIZE}" "${TEMPLATE}"; then
        echo "Resize failed — retrying with fallback"
        hdiutil resize -sectors 10167525 "${TEMPLATE}"
        hdiutil resize -sectors "${DMG_SIZE}" "${TEMPLATE}"
    fi

    attach_dmg
}

fixup_and_cleanup() {

    echo "Updating background"

    cp "${PACKAGING_DIR}/background.png" "${MOUNTPOINT}/."
    SetFile -a V "${MOUNTPOINT}/background.png"

    echo "Syncing filesystem"
    sync
    sleep 2

    detach_dmg

    echo "Reattaching to set auto-open"

    ATTACH_OUTPUT=$(hdiutil attach "${TEMPLATE}" -noautoopen -nobrowse)
    DEVICE=$(echo "$ATTACH_OUTPUT" | grep "^/dev/" | head -n1 | awk '{print $1}')

    if ! sysctl -n machdep.cpu.brand_string | grep Apple >/dev/null; then
        bless /Volumes/"${MOUNT_NAME}" --openfolder /Volumes/"${MOUNT_NAME}" || true
    fi

    sync
    sleep 2

    detach_dmg

    echo "Converting DMG"

    if [ -f "${DMG_NAME}" ]; then
        rm -f "${DMG_NAME}"
    fi

    hdiutil convert "${TEMPLATE}" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "${DMG_NAME}"

    rm -f "${TEMPLATE}"

    if [ -n "${SIGNING_IDENTITY:-}" ]; then
        codesign --sign "${SIGNING_IDENTITY}" --verbose "${DMG_NAME}"
    fi

    mkdir -p "${DMG_DIR}"

    mv "${DMG_NAME}" "${DMG_DIR}/"

    echo "DMG created: ${DMG_DIR}/${DMG_NAME}"
}

echo "PACKAGING_DIR: ${PACKAGING_DIR}"
echo "KICAD_SOURCE_DIR: ${KICAD_SOURCE_DIR}"
echo "KICAD_INSTALL_DIR: ${KICAD_INSTALL_DIR}"
echo "TEMPLATE: ${TEMPLATE}"
echo "DMG_DIR: ${DMG_DIR}"
echo "PACKAGE_TYPE: ${PACKAGE_TYPE}"

if [ ! -d "${PACKAGING_DIR}" ]; then
    echo "PACKAGING_DIR must exist"
    exit 1
fi

if [ -z "${TEMPLATE}" ]; then
    echo "TEMPLATE must be set"
    exit 1
fi

if [ -z "${DMG_DIR}" ]; then
    echo "DMG_DIR must be set"
    exit 1
fi

NOW=$(date +%Y%m%d-%H%M%S)

case "${PACKAGE_TYPE}" in
    unified)

        KICAD_GIT_REV=$(cd "${KICAD_SOURCE_DIR}" && git rev-parse --short HEAD)

        MOUNT_NAME="KiCad"
        MOUNTPOINT="kicad-mnt"

        DMG_SIZE=15567525

        if [ -z "${RELEASE_NAME:-}" ]; then
            DMG_NAME="kicad-unified-${NOW}-${KICAD_GIT_REV}.dmg"
        else
            DMG_NAME="kicad-unified-${RELEASE_NAME}.dmg"
        fi
    ;;
    *)
        echo "Unsupported PACKAGE_TYPE"
        exit 1
    ;;
esac

setup_dmg

mkdir -p "${MOUNTPOINT}/KiCad"

rsync -al "${KICAD_INSTALL_DIR}/" "${MOUNTPOINT}/KiCad/"

echo "Moving demos"
mv "${MOUNTPOINT}/KiCad/demos" "${MOUNTPOINT}/" || true

fixup_and_cleanup

echo "Done creating ${DMG_NAME}"