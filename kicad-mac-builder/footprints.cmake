if( DEFINED FOOTPRINTS_SOURCE_DIR AND NOT "${FOOTPRINTS_SOURCE_DIR}" STREQUAL "" )
    # Offline build: use a local checkout as-is (no git fetch, no network).
    ExternalProject_Add(
        footprints
        PREFIX  footprints
        SOURCE_DIR ${FOOTPRINTS_SOURCE_DIR}
        CMAKE_ARGS "-DCMAKE_INSTALL_PREFIX=<BINARY_DIR>/output"
    )
else()
    ExternalProject_Add(
        footprints
        PREFIX  footprints
        GIT_REPOSITORY ${FOOTPRINTS_URL}
        GIT_TAG ${FOOTPRINTS_TAG}
        CMAKE_ARGS "-DCMAKE_INSTALL_PREFIX=<BINARY_DIR>/output"
    )
endif()

ExternalProject_Get_Property(footprints BINARY_DIR)
set(footprints_INSTALL_DIR ${BINARY_DIR}/output)
