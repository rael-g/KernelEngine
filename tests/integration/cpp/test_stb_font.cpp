#include <gtest/gtest.h>
#include <kernel_engine/text/stb_truetype/stb_font.h>

class StbFontTest : public ::testing::Test {
protected:
    ke_font_loader_handle loader_h{};
    ke_font_loader* loader = nullptr;

    void SetUp() override {
        ke_font_loader_stb_params params{};
        params.logger = nullptr;

        loader_h = ke_font_loader_stb_create(&params, nullptr);
        ASSERT_NE(loader_h.ref, nullptr);
        loader = loader_h.ref;
    }

    void TearDown() override {
        if (loader_h.ref) {
            loader_h.destroy(loader_h.ref);
        }
    }
};

TEST_F(StbFontTest, Create_NullParams_ReturnsNull) {
    ke_font_loader_handle l = ke_font_loader_stb_create(nullptr, nullptr);
    ASSERT_EQ(l.ref, nullptr);
}

TEST_F(StbFontTest, LoadFont_NullPath_ReturnsNull) {
    ke_font_data* data = loader->load_font(loader, nullptr, 16.0f, 32, 96, 512, nullptr);
    ASSERT_EQ(data, nullptr);
}

TEST_F(StbFontTest, LoadFont_ZeroPixelSize_ReturnsNull) {
    ke_font_data* data = loader->load_font(loader, "test.ttf", 0.0f, 32, 96, 512, nullptr);
    ASSERT_EQ(data, nullptr);
}

TEST_F(StbFontTest, LoadFont_NegativePixelSize_ReturnsNull) {
    ke_font_data* data = loader->load_font(loader, "test.ttf", -1.0f, 32, 96, 512, nullptr);
    ASSERT_EQ(data, nullptr);
}

TEST_F(StbFontTest, LoadFont_ZeroCodepointCount_ReturnsNull) {
    ke_font_data* data = loader->load_font(loader, "test.ttf", 16.0f, 32, 0, 512, nullptr);
    ASSERT_EQ(data, nullptr);
}

TEST_F(StbFontTest, LoadFont_ZeroAtlasSize_ReturnsNull) {
    ke_font_data* data = loader->load_font(loader, "test.ttf", 16.0f, 32, 96, 0, nullptr);
    ASSERT_EQ(data, nullptr);
}

TEST_F(StbFontTest, LoadFont_Successful) {
    // No font ships with the repo, so probe the usual system locations. The
    // loader only needs some valid TTF; which one it is does not matter.
    const char* candidates[] = {
        "C:/Windows/Fonts/arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
    };

    for (const char* path : candidates) {
        ke_font_data* data = loader->load_font(loader, path, 16.0f, 32, 96, 512, nullptr);
        if (data != nullptr) {
            EXPECT_EQ(data->glyph_count, 96u);
            EXPECT_NE(data->atlas_rgba, nullptr);
            loader->free_font(loader, data);
            return;
        }
    }

    GTEST_SKIP() << "no system TTF font found in the probed locations";
}

TEST_F(StbFontTest, Destroy_NullHandle_IsSafe) {
    loader_h.destroy(nullptr);
}
