if( DEFINED TEMPLATES_SOURCE_DIR AND NOT "${TEMPLATES_SOURCE_DIR}" STREQUAL "" )
    # Offline build: use a local checkout as-is (no git fetch, no network).
    ExternalProject_Add(
        templates
        PREFIX  templates
        SOURCE_DIR ${TEMPLATES_SOURCE_DIR}
        CMAKE_ARGS "-DCMAKE_INSTALL_PREFIX=<BINARY_DIR>/output"
    )
else()
    ExternalProject_Add(
        templates
        PREFIX  templates
        GIT_REPOSITORY ${TEMPLATES_URL}
        GIT_TAG ${TEMPLATES_TAG}
        CMAKE_ARGS "-DCMAKE_INSTALL_PREFIX=<BINARY_DIR>/output"
    )
endif()

ExternalProject_Get_Property(templates BINARY_DIR)
set(templates_INSTALL_DIR ${BINARY_DIR}/output)
