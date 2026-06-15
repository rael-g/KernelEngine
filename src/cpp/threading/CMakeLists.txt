add_library(ke_threading
    src/ke_frame_sync.cpp
)

get_target_property(target_type ke_threading TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_threading PUBLIC KE_THREADING_STATIC)
else()
    target_compile_definitions(ke_threading PRIVATE KE_THREADING_EXPORT)
endif()

target_include_directories(ke_threading PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/src/c/threading/include>
    $<INSTALL_INTERFACE:include>
)

target_link_libraries(ke_threading PUBLIC
    ke_common
    ke_allocator
    ke_render
    ke_threading_default
)

if (WIN32)
    target_link_libraries(ke_threading PRIVATE kernel32)
endif()

install(TARGETS ke_threading
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
install(DIRECTORY ${CMAKE_SOURCE_DIR}/src/c/threading/include/ DESTINATION include)
