add_library(ke_framework
    src/world.c
)

target_include_directories(ke_framework PUBLIC
    ${CMAKE_SOURCE_DIR}/src/c/kernel/include
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

install(DIRECTORY include/ DESTINATION include)

target_link_libraries(ke_framework PUBLIC
    ke_kernel
    ke_runtime
)

get_target_property(target_type ke_framework TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_framework PUBLIC KE_FRAMEWORK_STATIC)
else()
    target_compile_definitions(ke_framework PRIVATE KE_FRAMEWORK_EXPORT)
endif()

install(TARGETS ke_framework
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
