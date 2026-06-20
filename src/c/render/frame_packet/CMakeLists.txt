add_library(ke_render_frame_packet STATIC
    src/frame_packet.c
)
add_library(ke::render_frame_packet ALIAS ke_render_frame_packet)

get_target_property(target_type ke_render_frame_packet TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_render_frame_packet PUBLIC KE_KERNEL_STATIC)
else()
    target_compile_definitions(ke_render_frame_packet PRIVATE KE_KERNEL_EXPORT)
endif()

target_link_libraries(ke_render_frame_packet PUBLIC ke_render ke_allocator ke_allocator_malloc)

install(TARGETS ke_render_frame_packet
    EXPORT KernelEngineTargets
    ARCHIVE DESTINATION lib
)
