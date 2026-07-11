// miniaudio is header-only. We're a standalone DLL so the single STB-style implementation define
// stays scoped to this translation unit — no symbol collision with any other plugin that might
// also pull miniaudio in.
#define MINIAUDIO_IMPLEMENTATION
#include <miniaudio.h>

#include "kernel_engine/audio/miniaudio/miniaudio_audio.h"
#include "kernel_engine/common/error.h"
#include "kernel_engine/allocator/allocator.h"
#include "kernel_engine/logger/logger.h"
#include "kernel_engine/resource_cache/resource_cache.h"

#include <mutex>
#include <unordered_map>
#include <cstring>

namespace {

struct LoadedSound
{
    ma_sound sound;
    bool     initialized;
};

// Sounds are refcounted and deduped by path through ke_resource_cache — the
// same kernel-built-in primitive the render core owns its texture/mesh/material
// caches through (see resource_cache.h: "each subsystem creates its OWN cache
// instance with a destroy_fn matching the subsystem's resource kind"). A second
// load_sound with the same path returns the already-loaded id, retained; the
// underlying ma_sound is only decoded once and only freed at refcount zero.
struct MiniAudioState
{
    ke_logger                                        *logger;
    ma_engine                                         engine;
    bool                                              engine_ready;
    std::mutex                                        mutex;             // guards sounds + next_id
    std::unordered_map<ke_audio_sound, LoadedSound *> sounds;
    ke_audio_sound                                    next_id;
    ke_resource_cache                                 *cache;
    void                                              (*cache_destroy)(ke_resource_cache *);
};

void log_warn(ke_logger *logger, const char *msg)
{
    if (!logger) return;
    ke_log_event ev{ KE_LOG_LEVEL_WARNING, "miniaudio", msg };
    logger->log(logger, &ev);
}

void log_info(ke_logger *logger, const char *msg)
{
    if (!logger) return;
    ke_log_event ev{ KE_LOG_LEVEL_INFO, "miniaudio", msg };
    logger->log(logger, &ev);
}

// ke_resource_cache destroy_fn: fires at refcount zero (a matching unload_sound
// call, or cache teardown for every still-live sound). ctx is the MiniAudioState.
void destroy_sound_resource(ke_resource_handle handle, void *ctx)
{
    auto *state = static_cast<MiniAudioState *>(ctx);
    LoadedSound *slot = nullptr;
    {
        std::lock_guard<std::mutex> lock(state->mutex);
        auto it = state->sounds.find(handle);
        if (it != state->sounds.end())
        {
            slot = it->second;
            state->sounds.erase(it);
        }
    }
    if (slot)
    {
        if (slot->initialized) ma_sound_uninit(&slot->sound);
        ke_free(slot);
    }
}

void audio_destroy(ke_audio *self)
{
    if (!self) return;
    auto *state = static_cast<MiniAudioState *>(self->handle);
    if (state)
    {
        // Fires destroy_sound_resource for every sound still referenced, which
        // uninits it and erases it from `sounds` — no separate teardown loop.
        if (state->cache) state->cache_destroy(state->cache);
        if (state->engine_ready) ma_engine_uninit(&state->engine);
        state->~MiniAudioState();
        ke_free(state);
    }
    // ke_audio struct itself is allocated by the factory and freed here too.
    // (state.allocator was captured above; can't use after free.)
}

ke_audio_sound audio_load_sound(ke_audio *self, const char *path, ke_error **out_error)
{
    if (!self || !path)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return KE_AUDIO_SOUND_INVALID;
    }

    auto *state = static_cast<MiniAudioState *>(self->handle);

    ke_resource_handle cached;
    if (state->cache->try_get_cached(state->cache, path, &cached))
        return static_cast<ke_audio_sound>(cached);

    auto *slot = static_cast<LoadedSound *>(ke_alloc(sizeof(LoadedSound), alignof(LoadedSound)));
    if (!slot)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "sound slot allocation failed");
        return KE_AUDIO_SOUND_INVALID;
    }
    std::memset(slot, 0, sizeof(*slot));

    ma_result r = ma_sound_init_from_file(&state->engine, path, 0, nullptr, nullptr, &slot->sound);
    if (r != MA_SUCCESS)
    {
        log_warn(state->logger, ma_result_description(r));
        ke_free(slot);
        KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "sound file not found or failed to load");
        return KE_AUDIO_SOUND_INVALID;
    }
    slot->initialized = true;

    ke_audio_sound id;
    {
        std::lock_guard<std::mutex> lock(state->mutex);
        if (state->next_id == 0) state->next_id = 1; // skip the invalid sentinel
        id = state->next_id++;
        state->sounds[id] = slot;
    }
    state->cache->register_resource(state->cache, id, nullptr);
    state->cache->cache_insert(state->cache, path, id, nullptr);

    return id;
}

void audio_unload_sound(ke_audio *self, ke_audio_sound id)
{
    if (!self || id == KE_AUDIO_SOUND_INVALID) return;
    auto *state = static_cast<MiniAudioState *>(self->handle);
    state->cache->release(state->cache, id, nullptr);
}

bool audio_play(ke_audio *self, ke_audio_sound id, float volume, ke_bool loop, ke_error **out_error)
{
    if (!self || id == KE_AUDIO_SOUND_INVALID)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return false;
    }
    auto *state = static_cast<MiniAudioState *>(self->handle);

    LoadedSound *slot = nullptr;
    {
        std::lock_guard<std::mutex> lock(state->mutex);
        auto it = state->sounds.find(id);
        if (it != state->sounds.end()) slot = it->second;
    }
    if (!slot || !slot->initialized)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "sound not loaded");
        return false;
    }

    // Re-trigger semantics: stop + rewind so play() on an already-playing handle restarts cleanly.
    ma_sound_stop(&slot->sound);
    ma_sound_seek_to_pcm_frame(&slot->sound, 0);
    ma_sound_set_volume(&slot->sound, volume);
    ma_sound_set_looping(&slot->sound, loop ? MA_TRUE : MA_FALSE);
    ma_result r = ma_sound_start(&slot->sound);
    if (r != MA_SUCCESS)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_GENERAL, "ma_sound_start failed");
        return false;
    }
    return true;
}

void audio_stop(ke_audio *self, ke_audio_sound id)
{
    if (!self || id == KE_AUDIO_SOUND_INVALID) return;
    auto *state = static_cast<MiniAudioState *>(self->handle);

    LoadedSound *slot = nullptr;
    {
        std::lock_guard<std::mutex> lock(state->mutex);
        auto it = state->sounds.find(id);
        if (it != state->sounds.end()) slot = it->second;
    }
    if (slot && slot->initialized) ma_sound_stop(&slot->sound);
}

void audio_set_master_volume(ke_audio *self, float volume)
{
    if (!self) return;
    auto *state = static_cast<MiniAudioState *>(self->handle);
    ma_engine_set_volume(&state->engine, volume);
}

} // namespace

extern "C" KE_AUDIO_MINIAUDIO_API ke_audio_handle ke_audio_miniaudio_create(
    const ke_audio_miniaudio_params *params, ke_error **out_error)
{
    if (!params)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return {nullptr, nullptr};
    }

    auto *state_mem = ke_alloc(sizeof(MiniAudioState), alignof(MiniAudioState));
    if (!state_mem)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "state allocation failed");
        return {nullptr, nullptr};
    }
    auto *state = new (state_mem) MiniAudioState{};
    state->logger       = params->logger;
    state->engine_ready = false;
    state->next_id      = 1;

    ma_engine_config cfg = ma_engine_config_init();
    ma_result r = ma_engine_init(&cfg, &state->engine);
    if (r != MA_SUCCESS)
    {
        log_warn(state->logger, ma_result_description(r));
        state->~MiniAudioState();
        ke_free(state);
        KE_ERROR_SET(out_error, &KE_ERROR_GENERAL, "engine init failed");
        return {nullptr, nullptr};
    }
    state->engine_ready = true;

    ke_resource_cache_params cache_params{ &destroy_sound_resource, state };
    ke_resource_cache_handle cache_h = ke_resource_cache_create(&cache_params, out_error);
    if (!cache_h.ref)
    {
        ma_engine_uninit(&state->engine);
        state->~MiniAudioState();
        ke_free(state);
        return {nullptr, nullptr};
    }
    state->cache         = cache_h.ref;
    state->cache_destroy = cache_h.destroy;

    auto *api = static_cast<ke_audio *>(ke_alloc(sizeof(ke_audio), alignof(ke_audio)));
    if (!api)
    {
        state->cache_destroy(state->cache);
        ma_engine_uninit(&state->engine);
        state->~MiniAudioState();
        ke_free(state);
        KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "api allocation failed");
        return {nullptr, nullptr};
    }
    std::memset(api, 0, sizeof(*api));
    api->handle            = state;
    api->load_sound        = &audio_load_sound;
    api->unload_sound      = &audio_unload_sound;
    api->play              = &audio_play;
    api->stop              = &audio_stop;
    api->set_master_volume = &audio_set_master_volume;

    log_info(state->logger, "miniaudio backend initialized");
    return {api, &audio_destroy};
}
