// miniaudio is header-only. We're a standalone DLL so the single STB-style implementation define
// stays scoped to this translation unit — no symbol collision with any other plugin that might
// also pull miniaudio in.
#define MINIAUDIO_IMPLEMENTATION
#include <miniaudio.h>

#include "kernel_engine/audio/miniaudio/miniaudio_audio.h"
#include "kernel_engine/common/error.h"
#include "kernel_engine/allocator/allocator.h"
#include "kernel_engine/logger/logger.h"

#include <mutex>
#include <unordered_map>
#include <cstring>

namespace {

struct LoadedSound
{
    ma_sound sound;
    bool     initialized;
};

struct MiniAudioState
{
    ke_allocator                                     *allocator;
    ke_logger                                        *logger;
    ma_engine                                         engine;
    bool                                              engine_ready;
    std::mutex                                        mutex;             // guards sounds + next_id
    std::unordered_map<ke_audio_sound, LoadedSound *> sounds;
    ke_audio_sound                                    next_id;
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

void audio_destroy(ke_audio *self)
{
    if (!self) return;
    auto *state = static_cast<MiniAudioState *>(self->handle);
    if (state)
    {
        {
            std::lock_guard<std::mutex> lock(state->mutex);
            for (auto &kv : state->sounds)
            {
                if (kv.second && kv.second->initialized) ma_sound_uninit(&kv.second->sound);
                if (kv.second) state->allocator->free(state->allocator, kv.second);
            }
            state->sounds.clear();
        }
        if (state->engine_ready) ma_engine_uninit(&state->engine);
        auto *alloc = state->allocator;
        state->~MiniAudioState();
        alloc->free(alloc, state);
    }
    // ke_audio struct itself is allocated by the factory and freed here too.
    // (state.allocator was captured above; can't use after free.)
}

ke_result audio_load_sound(ke_audio *self, const char *path, ke_audio_sound *out, ke_error **out_error)
{
    if (!self || !path || !out) return ke_error_set(out_error, &KE_ERROR_INVALID_ARGUMENT, "miniaudio", "invalid argument");
    *out = KE_AUDIO_SOUND_INVALID;

    auto *state = static_cast<MiniAudioState *>(self->handle);

    auto *slot = static_cast<LoadedSound *>(state->allocator->alloc(state->allocator, sizeof(LoadedSound), alignof(LoadedSound)));
    if (!slot) return ke_error_set(out_error, &KE_ERROR_OUT_OF_MEMORY, "miniaudio", "sound slot allocation failed");
    std::memset(slot, 0, sizeof(*slot));

    ma_result r = ma_sound_init_from_file(&state->engine, path, 0, nullptr, nullptr, &slot->sound);
    if (r != MA_SUCCESS)
    {
        log_warn(state->logger, ma_result_description(r));
        state->allocator->free(state->allocator, slot);
        return ke_error_set(out_error, &KE_ERROR_NOT_FOUND, "miniaudio", "sound file not found or failed to load");
    }
    slot->initialized = true;

    ke_audio_sound id;
    {
        std::lock_guard<std::mutex> lock(state->mutex);
        if (state->next_id == 0) state->next_id = 1; // skip the invalid sentinel
        id = state->next_id++;
        state->sounds[id] = slot;
    }

    *out = id;
    return KE_OK;
}

void audio_unload_sound(ke_audio *self, ke_audio_sound id)
{
    if (!self || id == KE_AUDIO_SOUND_INVALID) return;
    auto *state = static_cast<MiniAudioState *>(self->handle);

    LoadedSound *slot = nullptr;
    {
        std::lock_guard<std::mutex> lock(state->mutex);
        auto it = state->sounds.find(id);
        if (it != state->sounds.end())
        {
            slot = it->second;
            state->sounds.erase(it);
        }
    }
    if (slot)
    {
        if (slot->initialized) ma_sound_uninit(&slot->sound);
        state->allocator->free(state->allocator, slot);
    }
}

ke_result audio_play(ke_audio *self, ke_audio_sound id, float volume, ke_bool loop, ke_error **out_error)
{
    if (!self || id == KE_AUDIO_SOUND_INVALID) return ke_error_set(out_error, &KE_ERROR_INVALID_ARGUMENT, "miniaudio", "invalid argument");
    auto *state = static_cast<MiniAudioState *>(self->handle);

    LoadedSound *slot = nullptr;
    {
        std::lock_guard<std::mutex> lock(state->mutex);
        auto it = state->sounds.find(id);
        if (it != state->sounds.end()) slot = it->second;
    }
    if (!slot || !slot->initialized) return ke_error_set(out_error, &KE_ERROR_NOT_FOUND, "miniaudio", "sound not loaded");

    // Re-trigger semantics: stop + rewind so play() on an already-playing handle restarts cleanly.
    ma_sound_stop(&slot->sound);
    ma_sound_seek_to_pcm_frame(&slot->sound, 0);
    ma_sound_set_volume(&slot->sound, volume);
    ma_sound_set_looping(&slot->sound, loop ? MA_TRUE : MA_FALSE);
    ma_result r = ma_sound_start(&slot->sound);
    return (r == MA_SUCCESS) ? KE_OK : ke_error_set(out_error, &KE_ERROR_GENERAL, "miniaudio", "ma_sound_start failed");
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

extern "C" KE_AUDIO_MINIAUDIO_API ke_result ke_audio_miniaudio_create(
    const ke_audio_miniaudio_params *params, ke_audio **out, ke_error **out_error)
{
    if (!params || !params->allocator || !out) return ke_error_set(out_error, &KE_ERROR_INVALID_ARGUMENT, "miniaudio", "invalid argument");
    auto *alloc = params->allocator;

    auto *state_mem = alloc->alloc(alloc, sizeof(MiniAudioState), alignof(MiniAudioState));
    if (!state_mem) return ke_error_set(out_error, &KE_ERROR_OUT_OF_MEMORY, "miniaudio", "state allocation failed");
    auto *state = new (state_mem) MiniAudioState{};
    state->allocator    = alloc;
    state->logger       = params->logger;
    state->engine_ready = false;
    state->next_id      = 1;

    ma_engine_config cfg = ma_engine_config_init();
    ma_result r = ma_engine_init(&cfg, &state->engine);
    if (r != MA_SUCCESS)
    {
        log_warn(state->logger, ma_result_description(r));
        state->~MiniAudioState();
        alloc->free(alloc, state);
        return ke_error_set(out_error, &KE_ERROR_GENERAL, "miniaudio", "engine init failed");
    }
    state->engine_ready = true;

    auto *api = static_cast<ke_audio *>(alloc->alloc(alloc, sizeof(ke_audio), alignof(ke_audio)));
    if (!api)
    {
        ma_engine_uninit(&state->engine);
        state->~MiniAudioState();
        alloc->free(alloc, state);
        return ke_error_set(out_error, &KE_ERROR_OUT_OF_MEMORY, "miniaudio", "api allocation failed");
    }
    std::memset(api, 0, sizeof(*api));
    api->handle            = state;
    api->destroy           = &audio_destroy;
    api->load_sound        = &audio_load_sound;
    api->unload_sound      = &audio_unload_sound;
    api->play              = &audio_play;
    api->stop              = &audio_stop;
    api->set_master_volume = &audio_set_master_volume;

    log_info(state->logger, "miniaudio backend initialized");
    *out = api;
    return KE_OK;
}
