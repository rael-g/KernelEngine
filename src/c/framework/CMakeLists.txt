set(FRAMEWORK_SOURCES
    src/framework.c
)

add_library(ke_framework ${FRAMEWORK_SOURCES})

get_target_property(target_type ke_framework TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_framework PUBLIC KE_FRAMEWORK_STATIC)
else()
    target_compile_definitions(ke_framework PRIVATE KE_FRAMEWORK_EXPORT)
endif()

target_include_directories(ke_framework PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

# Framework primitives are built on top of kernel contracts.
target_link_libraries(ke_framework PUBLIC ke_kernel)

add_library(ke::framework ALIAS ke_framework)

install(TARGETS ke_framework
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
