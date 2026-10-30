if( DEFINED PACKAGES3D_SOURCE_DIR AND NOT "${PACKAGES3D_SOURCE_DIR}" STREQUAL "" )
    # Offline build: use a local checkout as-is (no git fetch, no network).
    ExternalProject_Add(
        packages3d
        PREFIX  packages3d
        SOURCE_DIR ${PACKAGES3D_SOURCE_DIR}
        CMAKE_ARGS "-DCMAKE_INSTALL_PREFIX=<BINARY_DIR>/output"
    )
else()
    ExternalProject_Add(
        packages3d
        PREFIX  packages3d
        GIT_REPOSITORY ${PACKAGES3D_URL}
        GIT_TAG ${PACKAGES3D_TAG}
        #GIT_PROGRESS 1 #TODO uncomment when the official KiCad CMake gets updated...
        CMAKE_ARGS "-DCMAKE_INSTALL_PREFIX=<BINARY_DIR>/output"
    )
endif()

ExternalProject_Get_Property(packages3d BINARY_DIR)
set(packages3d_INSTALL_DIR ${BINARY_DIR}/output)
