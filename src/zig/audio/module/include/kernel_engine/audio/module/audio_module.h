
#pragma once

#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/framework/world.h>

#ifndef KE_AUDIO_MODULE_API
#  if defined(_WIN32) || defined(__CYGWIN__)
#    if defined(KE_AUDIO_MODULE_STATIC)
#      define KE_AUDIO_MODULE_API
#    elif defined(KE_AUDIO_MODULE_EXPORT)
#      define KE_AUDIO_MODULE_API __declspec(dllexport)
#    else
#      define KE_AUDIO_MODULE_API __declspec(dllimport)
#    endif
#  else
#    define KE_AUDIO_MODULE_API __attribute__((visibility("default")))
#  endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// @brief Registers audio's component ids and their scene-file field tables against
///        @p world, so an [entity.components.audio_player] block applies.
/// @return false if either argument is NULL.
KE_AUDIO_MODULE_API bool ke_audio_register_scene_apply(ke_ecs *ecs, ke_world *world);

#ifdef __cplusplus
}
#endif
