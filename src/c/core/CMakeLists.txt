set(CORE_SOURCES
    src/context/allocator.c
    src/common/hash_map.c
    src/common/hash.c
    src/engine/engine.c
    src/messaging/message_pipe.c
    src/logger/logger.c
    src/input/input.c
)

add_library(ke_core ${CORE_SOURCES})

get_target_property(target_type ke_core TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_core PUBLIC KE_CORE_STATIC)
else()
    target_compile_definitions(ke_core PRIVATE KE_CORE_EXPORT)
endif()

target_include_directories(ke_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

add_library(ke::core ALIAS ke_core)

install(TARGETS ke_core
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
