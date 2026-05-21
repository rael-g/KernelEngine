add_library(ke_dev_platform_win32 SHARED
    src/win32_dev_platform.cpp
)

target_include_directories(ke_dev_platform_win32 PRIVATE
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    include
    src
)

target_link_libraries(ke_dev_platform_win32 PRIVATE ke_kernel kernel32)

target_compile_definitions(ke_dev_platform_win32 PRIVATE KE_DEV_PLATFORM_EXPORT)

install(TARGETS ke_dev_platform_win32
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
