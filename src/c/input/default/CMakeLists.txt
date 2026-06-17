add_library(ke_input_default
    src/input_default.c
)
add_library(ke::input_default ALIAS ke_input_default)

get_target_property(target_type ke_input_default TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_input_default PUBLIC KE_INPUT_STATIC)
else()
    target_compile_definitions(ke_input_default PRIVATE KE_INPUT_EXPORT)
endif()

target_link_libraries(ke_input_default PUBLIC ke_input ke_allocator ke_allocator_malloc)

install(TARGETS ke_input_default
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
