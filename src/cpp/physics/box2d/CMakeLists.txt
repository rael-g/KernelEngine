add_library(ke_physics_2d_box2d
    src/box2d_physics.cpp
)

get_target_property(target_type ke_physics_2d_box2d TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_physics_2d_box2d PUBLIC KE_PHYSICS_BOX2D_STATIC)
else()
    target_compile_definitions(ke_physics_2d_box2d PRIVATE KE_PHYSICS_BOX2D_EXPORT)
endif()

target_include_directories(ke_physics_2d_box2d PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_include_directories(ke_physics_2d_box2d PRIVATE
    src
)

find_package(box2d CONFIG REQUIRED)

target_link_libraries(ke_physics_2d_box2d PUBLIC
    ke_physics
    ke_logger
)

target_link_libraries(ke_physics_2d_box2d PRIVATE
    box2d::box2d
)

install(TARGETS ke_physics_2d_box2d
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
