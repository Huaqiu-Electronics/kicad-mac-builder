if( DEFINED SYMBOLS_SOURCE_DIR AND NOT "${SYMBOLS_SOURCE_DIR}" STREQUAL "" )
    # Offline build: use a local checkout as-is (no git fetch, no network).
    ExternalProject_Add(
        symbols
        PREFIX  symbols
        SOURCE_DIR ${SYMBOLS_SOURCE_DIR}
        CMAKE_ARGS "-DCMAKE_INSTALL_PREFIX=<BINARY_DIR>/output"
    )
else()
    ExternalProject_Add(
        symbols
        PREFIX  symbols
        GIT_REPOSITORY ${SYMBOLS_URL}
        GIT_TAG ${SYMBOLS_TAG}
        CMAKE_ARGS "-DCMAKE_INSTALL_PREFIX=<BINARY_DIR>/output"
    )
endif()

ExternalProject_Get_Property(symbols BINARY_DIR)
set(symbols_INSTALL_DIR ${BINARY_DIR}/output)
