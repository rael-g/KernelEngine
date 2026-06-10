add_library(ke_runtime
    src/runtime.c
)

target_include_directories(ke_runtime PUBLIC
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
)

target_link_libraries(ke_runtime PUBLIC
    ke_kernel
)

install(TARGETS ke_runtime
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
