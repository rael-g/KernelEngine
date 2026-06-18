add_library(ke_text_stb_truetype
    src/stb_font.cpp
)

get_target_property(target_type ke_text_stb_truetype TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_text_stb_truetype PUBLIC KE_TEXT_STB_TRUETYPE_STATIC)
else()
    target_compile_definitions(ke_text_stb_truetype PRIVATE KE_TEXT_STB_TRUETYPE_EXPORT)
endif()

target_include_directories(ke_text_stb_truetype PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_include_directories(ke_text_stb_truetype PRIVATE
    src
)

# stb is header-only in vcpkg. STB_TRUETYPE_IMPLEMENTATION is defined inside stb_font.cpp;
# this is the only translation unit that compiles the implementation.
find_path(STB_INCLUDE_DIR "stb_truetype.h" REQUIRED)
target_include_directories(ke_text_stb_truetype PRIVATE ${STB_INCLUDE_DIR})

target_link_libraries(ke_text_stb_truetype PUBLIC
    ke_text
    ke_logger
)
target_link_libraries(ke_text_stb_truetype PRIVATE ke_allocator_malloc)

install(TARGETS ke_text_stb_truetype
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
