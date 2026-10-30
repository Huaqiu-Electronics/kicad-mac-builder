if(NOT(KICAD_SOURCE_DIR))
    set(PACKAGE_KICAD_SOURCE_DIR ${CMAKE_BINARY_DIR}/kicad/src/kicad)
else()
    set(PACKAGE_KICAD_SOURCE_DIR ${KICAD_SOURCE_DIR})
endif()

set( PACKAGE_KICAD_UNIFIED_DEPS kicad symbols footprints templates packages3d )
if( KMB_ENABLE_DOCS )
    list( APPEND PACKAGE_KICAD_UNIFIED_DEPS docs )
endif()

ExternalProject_Add(
    package-kicad-unified
    DEPENDS ${PACKAGE_KICAD_UNIFIED_DEPS}
    PREFIX package-kicad-unified
    DOWNLOAD_COMMAND ""
    UPDATE_COMMAND   ""
    PATCH_COMMAND ""
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND VERBOSE=1
                    PACKAGING_DIR=${CMAKE_SOURCE_DIR}/unified-packaging
                    KICAD_SOURCE_DIR=${PACKAGE_KICAD_SOURCE_DIR}
                    KICAD_INSTALL_DIR=${KICAD_INSTALL_DIR}
                    TEMPLATE=kicadtemplate.dmg
                    PACKAGE_TYPE=unified
                    DMG_DIR=${DMG_DIR}
                    RELEASE_NAME=${RELEASE_NAME}
                    SIGNING_IDENTITY=${SIGNING_IDENTITY}
                    APPLE_DEVELOPER_USERNAME=${APPLE_DEVELOPER_USERNAME}
                    APPLE_DEVELOPER_PASSWORD_KEYCHAIN_NAME=${APPLE_DEVELOPER_PASSWORD_KEYCHAIN_NAME}
                    DMG_NOTARIZATION_ID=${DMG_NOTARIZATION_ID}
                    ASC_PROVIDER=${ASC_PROVIDER}
                    ${BIN_DIR}/package.sh
)

SET_TARGET_PROPERTIES(package-kicad-unified PROPERTIES EXCLUDE_FROM_ALL True)