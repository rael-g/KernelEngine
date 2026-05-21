# cmake/Coverage.cmake

function(enable_coverage target)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" OR CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang" OR CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        message(STATUS "Enabling coverage for target ${target} (Clang/GCC)")
        target_compile_options(${target} PRIVATE --coverage -fprofile-arcs -ftest-coverage)
        target_link_libraries(${target} PRIVATE --coverage)
    elseif(MSVC)
        message(STATUS "Enabling coverage for target ${target} (MSVC)")
    endif()
endfunction()

# Add a global option to enable coverage
option(KE_COVERAGE "Enable code coverage reporting" OFF)

if(KE_COVERAGE)
    message(STATUS "Code coverage reporting is ENABLED")
endif()
