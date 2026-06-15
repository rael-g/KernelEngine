add_library(ke_audio_miniaudio
    src/miniaudio_audio.cpp
)

get_target_property(target_type ke_audio_miniaudio TYPE)
if (target_type STREQUAL "STATIC_LIBRARY")
    target_compile_definitions(ke_audio_miniaudio PUBLIC KE_AUDIO_MINIAUDIO_STATIC)
else()
    target_compile_definitions(ke_audio_miniaudio PRIVATE KE_AUDIO_MINIAUDIO_EXPORT)
endif()

target_include_directories(ke_audio_miniaudio PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_include_directories(ke_audio_miniaudio PRIVATE
    src
)

# miniaudio is header-only in vcpkg. MINIAUDIO_IMPLEMENTATION is defined in miniaudio_audio.cpp;
# as a standalone DLL, this is the only TU that compiles the implementation.
find_path(MINIAUDIO_INCLUDE_DIR "miniaudio.h" REQUIRED)
target_include_directories(ke_audio_miniaudio PRIVATE ${MINIAUDIO_INCLUDE_DIR})

target_link_libraries(ke_audio_miniaudio PUBLIC
    ke_audio
    ke_logger
)

# miniaudio uses the OS audio APIs; on Windows that's WASAPI/DSound and brings in winmm.
if (WIN32)
    target_link_libraries(ke_audio_miniaudio PRIVATE winmm)
endif()

install(TARGETS ke_audio_miniaudio
    EXPORT KernelEngineTargets
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/ DESTINATION include)
