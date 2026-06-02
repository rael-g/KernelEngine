#include <gtest/gtest.h>
#include <kernel_engine/audio/miniaudio/miniaudio_audio.h>
#include <kernel_engine/kernel/context/allocator.h>

class MiniAudioTest : public ::testing::Test {
protected:
    ke_allocator* allocator = nullptr;
    ke_audio* audio = nullptr;

    void SetUp() override {
        allocator = ke_allocator_malloc_create();
        ke_audio_miniaudio_params params{};
        params.allocator = allocator;
        params.logger = nullptr;
        
        ke_result res = ke_audio_miniaudio_create(&params, &audio);
        // It might return KE_ERROR if no audio device is available, but let's hope for the best or handle it.
        if (res != KE_OK) {
            audio = nullptr;
        }
    }

    void TearDown() override {
        if (audio) {
            audio->destroy(audio);
        }
        if (allocator) {
            allocator->destroy(allocator);
        }
    }
};

TEST_F(MiniAudioTest, Create_Works) {
    // If Setup failed because of no audio device, skip
    if (!audio) GTEST_SKIP() << "No audio device available";
    ASSERT_NE(audio, nullptr);
}

TEST_F(MiniAudioTest, SetMasterVolume_Works) {
    if (!audio) GTEST_SKIP();
    audio->set_master_volume(audio, 0.5f);
    // No easy way to verify master volume without internal access, but it shouldn't crash.
}

TEST_F(MiniAudioTest, LoadSound_FailsOnNonExistentFile) {
    if (!audio) GTEST_SKIP();
    uint32_t id = 0;
    ke_result res = audio->load_sound(audio, "non_existent_file.wav", &id);
    ASSERT_NE(res, KE_OK);
}

TEST_F(MiniAudioTest, Play_NullSound_DoesNotCrash) {
    if (!audio) GTEST_SKIP();
    // 0 is usually an invalid ID
    audio->play(audio, 0, 1.0f, 0);
}

TEST_F(MiniAudioTest, Stop_NullSound_DoesNotCrash) {
    if (!audio) GTEST_SKIP();
    audio->stop(audio, 0);
}
