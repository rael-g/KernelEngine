add_library(ke_common src/error.c)
add_library(ke::common ALIAS ke_common)

get_target_property(target_type ke_common TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_common PUBLIC KE_COMMON_STATIC)
else()
    target_compile_definitions(ke_common PRIVATE KE_COMMON_EXPORT)
endif()

# ke_error_copy() heap-owns an error snapshot via the internal allocator.
target_link_libraries(ke_common PRIVATE ke_allocator ke_allocator_malloc)

target_include_directories(ke_common PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
install(TARGETS ke_common
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
install(DIRECTORY include/ DESTINATION include)
