# ke_framework — API layer. Headers only (vtable contracts under
# include/kernel_engine/framework/). Implementations + factories live in
# plugin libs under src/cpp/framework/<concept>/. Consumers link this for
# the include path; runtime linkage is plugin-specific.
add_library(ke_framework INTERFACE)

target_include_directories(ke_framework INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_link_libraries(ke_framework INTERFACE ke_kernel)

add_library(ke::framework ALIAS ke_framework)

install(TARGETS ke_framework EXPORT KernelEngineTargets)
install(DIRECTORY include/ DESTINATION include)
