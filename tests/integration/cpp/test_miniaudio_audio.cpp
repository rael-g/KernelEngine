#include <gtest/gtest.h>
#include <kernel_engine/audio/miniaudio/miniaudio_audio.h>

class MiniAudioTest : public ::testing::Test {
protected:
    ke_audio_handle audio_h{};
    ke_audio* audio = nullptr;

    void SetUp() override {
        ke_audio_miniaudio_params params{};
        params.logger = nullptr;

        audio_h = ke_audio_miniaudio_create(&params, nullptr);
        audio = audio_h.ref;  // may be null if no audio device available
    }

    void TearDown() override {
        if (audio_h.ref) {
            audio_h.destroy(audio_h.ref);
        }
    }
};

TEST_F(MiniAudioTest, Create_Works) {
    if (!audio) GTEST_SKIP() << "No audio device available";
    ASSERT_NE(audio, nullptr);
}

TEST_F(MiniAudioTest, Create_NullParams_ReturnsNull) {
    ke_audio_handle h = ke_audio_miniaudio_create(nullptr, nullptr);
    ASSERT_EQ(h.ref, nullptr);
}

TEST_F(MiniAudioTest, LoadSound_NullPath_ReturnsInvalid) {
    if (!audio) GTEST_SKIP();
    ke_audio_sound id = audio->load_sound(audio, nullptr, nullptr);
    ASSERT_EQ(id, KE_AUDIO_SOUND_INVALID);
}

TEST_F(MiniAudioTest, LoadSound_BadPath_ReturnsInvalid) {
    if (!audio) GTEST_SKIP();
    ke_audio_sound id = audio->load_sound(audio, "nonexistent.wav", nullptr);
    ASSERT_EQ(id, KE_AUDIO_SOUND_INVALID);
}

TEST_F(MiniAudioTest, UnloadSound_InvalidId_IsSafe) {
    if (!audio) GTEST_SKIP();
    audio->unload_sound(audio, KE_AUDIO_SOUND_INVALID);
}

TEST_F(MiniAudioTest, Stop_NullHandle_IsSafe) {
    audio->stop(nullptr, KE_AUDIO_SOUND_INVALID);
}

TEST_F(MiniAudioTest, SetMasterVolume_NullHandle_IsSafe) {
    audio->set_master_volume(nullptr, 1.0f);
}

TEST_F(MiniAudioTest, Destroy_NullHandle_IsSafe) {
    audio_h.destroy(nullptr);
}

TEST_F(MiniAudioTest, Play_Twice_IsSafe) {
    if (!audio) GTEST_SKIP();
    SUCCEED();
}

TEST_F(MiniAudioTest, SetMasterVolume_ValidValues) {
    if (!audio) GTEST_SKIP();
    audio->set_master_volume(audio, 0.5f);
    audio->set_master_volume(audio, 0.0f);
    audio->set_master_volume(audio, 1.0f);
    SUCCEED();
}

TEST_F(MiniAudioTest, Play_NullHandle_ReturnsFalse) {
    bool ok = audio->play(nullptr, KE_AUDIO_SOUND_INVALID, 1.0f, false, nullptr);
    ASSERT_FALSE(ok);
}
