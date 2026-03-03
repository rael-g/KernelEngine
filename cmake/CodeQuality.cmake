# cmake/CodeQuality.cmake
#
# Defines targets for C/C++ code quality checks (clang-format and clang-tidy).
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_program(CLANG_FORMAT_EXECUTABLE clang-format)
find_program(CLANG_TIDY_EXECUTABLE clang-tidy)

if(CLANG_FORMAT_EXECUTABLE OR CLANG_TIDY_EXECUTABLE)
    file(GLOB_RECURSE C_SOURCE_FILES
        CONFIGURE_DEPENDS
        "${CMAKE_SOURCE_DIR}/src/c/*.c"
        "${CMAKE_SOURCE_DIR}/examples/*.c"
    )
    file(GLOB_RECURSE CPP_SOURCE_FILES
        CONFIGURE_DEPENDS
        "${CMAKE_SOURCE_DIR}/src/cpp/*.cc"
        "${CMAKE_SOURCE_DIR}/src/cpp/*.hh"
        "${CMAKE_SOURCE_DIR}/src/cpp/*.cpp"
        "${CMAKE_SOURCE_DIR}/src/cpp/*.h"
        "${CMAKE_SOURCE_DIR}/tests/*.cpp"
        "${CMAKE_SOURCE_DIR}/tests/*.h"
    )
    # Headers are shared but we must be careful with C headers in src/c
    file(GLOB_RECURSE C_HEADERS
        CONFIGURE_DEPENDS
        "${CMAKE_SOURCE_DIR}/src/c/*.h"
        "${CMAKE_SOURCE_DIR}/examples/*.h"
    )
    
    set(ALL_SOURCE_FILES ${C_SOURCE_FILES} ${CPP_SOURCE_FILES} ${C_HEADERS})
endif()

if(CLANG_FORMAT_EXECUTABLE)
    add_custom_target(clang_format_fix
        COMMAND ${CLANG_FORMAT_EXECUTABLE} -i ${ALL_SOURCE_FILES}
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        COMMENT "Formatting source files with clang-format..."
    )
endif()

if(CLANG_TIDY_EXECUTABLE)
    # Target for C files
    add_custom_target(clang_tidy_fix_c
        COMMAND ${CLANG_TIDY_EXECUTABLE}
            ${C_SOURCE_FILES}
            ${C_HEADERS}
            -p ${CMAKE_BINARY_DIR}
            -header-filter=^${CMAKE_SOURCE_DIR}/src/
            -system-headers=false
            --fix
            --fix-errors
            -extra-arg=-xc
            -extra-arg=-std=c11
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        COMMENT "Running clang-tidy fix on C files..."
    )

    # Target for C++ files
    add_custom_target(clang_tidy_fix_cpp
        COMMAND ${CLANG_TIDY_EXECUTABLE}
            ${CPP_SOURCE_FILES}
            -p ${CMAKE_BINARY_DIR}
            -header-filter=^${CMAKE_SOURCE_DIR}/src/
            -system-headers=false
            --fix
            --fix-errors
            -extra-arg=-xc++
            -extra-arg=-std=c++17
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        COMMENT "Running clang-tidy fix on C++ files..."
    )

    add_custom_target(clang_tidy_fix
        DEPENDS clang_tidy_fix_c clang_tidy_fix_cpp
    )
endif()
