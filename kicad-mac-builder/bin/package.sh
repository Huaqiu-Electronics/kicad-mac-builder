#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cleanup() {
    echo "Cleaning up mounted DMG..."

    if mount | grep -q "${MOUNTPOINT}" ; then
        echo "Detaching ${MOUNTPOINT}"
        for i in {1..10}; do
            if hdiutil detach "${MOUNTPOINT}" -force 2>/dev/null; then
                break
            fi
            echo "Retry detach ${MOUNTPOINT} ($i)"
            lsof "${MOUNTPOINT}" || true
            pkill -f diskimages-helper || true
            sync
            sleep 2
        done
    fi

    if mount | grep -q "/Volumes/${MOUNT_NAME}" ; then
        echo "Detaching /Volumes/${MOUNT_NAME}"
        for i in {1..10}; do
            if hdiutil detach "/Volumes/${MOUNT_NAME}" -force 2>/dev/null; then
                break
            fi
            echo "Retry detach /Volumes/${MOUNT_NAME} ($i)"
            lsof "/Volumes/${MOUNT_NAME}" || true
            pkill -f diskimages-helper || true
            sync
            sleep 2
        done
    fi
}

trap cleanup EXIT

setup_dmg() {

    if [ -d "${MOUNTPOINT}" ]; then
        rm -rf "${MOUNTPOINT}"
    fi

    mkdir -p "${MOUNTPOINT}"

    if [ -f "${TEMPLATE}" ]; then
        rm "${TEMPLATE}"
    fi

    echo "Extracting template DMG..."
    tar xf "${PACKAGING_DIR}/${TEMPLATE}.tar.bz2"

    if [ ! -f "${TEMPLATE}" ]; then
        echo "ERROR: ${TEMPLATE} not found after extraction"
        exit 1
    fi

    echo "Resizing DMG..."
    hdiutil resize -sectors "${DMG_SIZE}" "${TEMPLATE}" || {
        echo "Resize failed, retrying..."
        hdiutil resize -limits "${TEMPLATE}" || true
        hdiutil resize -sectors "${DMG_SIZE}" "${TEMPLATE}"
    }

    diskutil unmount "/Volumes/${MOUNT_NAME}" 2>/dev/null || true

    echo "Mounting DMG..."
    hdiutil attach "${TEMPLATE}" -noautoopen -mountpoint "${MOUNTPOINT}"
}

fixup_and_cleanup() {

    echo "Updating DMG background..."

    cp "${PACKAGING_DIR}/background.png" "${MOUNTPOINT}/"
    SetFile -a V "${MOUNTPOINT}/background.png"

    echo "Detaching build mount..."
    hdiutil detach "${MOUNTPOINT}" -force

    rm -rf "${MOUNTPOINT}"

    echo "Mounting DMG for blessing..."
    hdiutil attach "${TEMPLATE}" -noautoopen -nobrowse -mountpoint "/Volumes/${MOUNT_NAME}"

    if ! sysctl -n machdep.cpu.brand_string | grep Apple >/dev/null; then
        bless "/Volumes/${MOUNT_NAME}" --openfolder "/Volumes/${MOUNT_NAME}"
    fi

    echo "Unmounting blessed DMG..."
    for i in {1..12}; do
        if hdiutil detach "/Volumes/${MOUNT_NAME}" -force 2>/dev/null; then
            break
        fi
        echo "Retry unmount /Volumes/${MOUNT_NAME} ($i)"
        lsof "/Volumes/${MOUNT_NAME}" || true
        pkill -f diskimages-helper || true
        sync
        sleep 5
    done

    echo "Compressing DMG..."

    if [ -f "${DMG_NAME}" ]; then
        rm -f "${DMG_NAME}"
    fi

    hdiutil convert "${TEMPLATE}" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "${DMG_NAME}"

    rm "${TEMPLATE}"

    if [ -n "${SIGNING_IDENTITY:-}" ]; then
        echo "Codesigning DMG..."
        codesign --sign "${SIGNING_IDENTITY}" --verbose "${DMG_NAME}"
    fi

    if [ -n "${SIGNING_IDENTITY:-}" ] &&
       [ -n "${APPLE_DEVELOPER_USERNAME:-}" ] &&
       [ -n "${APPLE_DEVELOPER_PASSWORD_KEYCHAIN_NAME:-}" ] &&
       [ -n "${DMG_NOTARIZATION_ID:-}" ] &&
       [ -n "${ASC_PROVIDER:-}" ]; then

        echo "Submitting for notarization..."

        "${SCRIPT_DIR}/apple.py" notarize \
            --apple-developer-username "${APPLE_DEVELOPER_USERNAME}" \
            --apple-developer-password-keychain-name "${APPLE_DEVELOPER_PASSWORD_KEYCHAIN_NAME}" \
            --notarization-id "${DMG_NOTARIZATION_ID}" \
            --asc-provider "${ASC_PROVIDER}" \
            "${DMG_NAME}"
    fi

    mkdir -p "${DMG_DIR}"

    mv "${DMG_NAME}" "${DMG_DIR}/"

}

set -x

NOW=$(date +%Y%m%d-%H%M%S)

case "${PACKAGE_TYPE}" in
    unified)
        KICAD_GIT_REV=$(cd "${KICAD_SOURCE_DIR}" && git rev-parse --short HEAD)
        MOUNT_NAME="KiCad"
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
esac

MOUNTPOINT="kicad-mnt"

setup_dmg

echo "Copying KiCad bundle..."

mkdir -p "${MOUNTPOINT}/KiCad"

rsync -al "${KICAD_INSTALL_DIR}/" "${MOUNTPOINT}/KiCad/"

echo "Moving demos..."
mv "${MOUNTPOINT}/KiCad/demos" "${MOUNTPOINT}/" || true

fixup_and_cleanup

echo "Done creating ${DMG_NAME} in ${DMG_DIR}"