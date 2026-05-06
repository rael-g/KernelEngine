add_library(ke_dev_platform_posix SHARED
    src/posix_dev_platform.cpp
)

target_include_directories(ke_dev_platform_posix PRIVATE
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    src
)

target_link_libraries(ke_dev_platform_posix PRIVATE ke_kernel)

if (NOT APPLE)
    target_link_libraries(ke_dev_platform_posix PRIVATE pthread)
endif()

install(TARGETS ke_dev_platform_posix
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
