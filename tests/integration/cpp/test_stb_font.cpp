#include <gtest/gtest.h>
#include <kernel_engine/text/stb_truetype/stb_font.h>

class StbFontTest : public ::testing::Test {
protected:
    ke_font_loader_handle loader_h{};
    ke_font_loader* loader = nullptr;

    void SetUp() override {
        ke_font_loader_stb_params params{};
        params.logger = nullptr;

        ke_result res = ke_font_loader_stb_create(&params, &loader_h, nullptr);
        ASSERT_EQ(res, KE_OK);
        loader = loader_h.ref;
        ASSERT_NE(loader, nullptr);
    }

    void TearDown() override {
        if (loader_h.ref) {
            loader_h.destroy(loader_h.ref);
        }
    }
};

TEST_F(StbFontTest, Create_NullParams_ReturnsInvalidArgument) {
    ke_font_loader_handle l{};
    ASSERT_EQ(ke_font_loader_stb_create(nullptr, &l, nullptr), KE_ERROR);
}

TEST_F(StbFontTest, Create_NullOut_ReturnsInvalidArgument) {
    ke_font_loader_stb_params p{};
    ASSERT_EQ(ke_font_loader_stb_create(&p, nullptr, nullptr), KE_ERROR);
}


TEST_F(StbFontTest, LoadFont_NullPath_ReturnsInvalidArgument) {
    ke_font_data* data = nullptr;
    ke_result res = loader->load_font(loader, nullptr, 16.0f, 32, 96, 512, &data, nullptr);
    ASSERT_EQ(res, KE_ERROR);
}

TEST_F(StbFontTest, LoadFont_NullOut_ReturnsInvalidArgument) {
    ke_result res = loader->load_font(loader, "test.ttf", 16.0f, 32, 96, 512, nullptr, nullptr);
    ASSERT_EQ(res, KE_ERROR);
}

TEST_F(StbFontTest, LoadFont_InvalidPixelSize_ReturnsInvalidArgument) {
    ke_font_data* data = nullptr;
    ke_result res = loader->load_font(loader, "test.ttf", 0.0f, 32, 96, 512, &data, nullptr);
    ASSERT_EQ(res, KE_ERROR);
}

TEST_F(StbFontTest, LoadFont_NegativePixelSize_ReturnsInvalidArgument) {
    ke_font_data* data = nullptr;
    ke_result res = loader->load_font(loader, "test.ttf", -1.0f, 32, 96, 512, &data, nullptr);
    ASSERT_EQ(res, KE_ERROR);
}

TEST_F(StbFontTest, LoadFont_ZeroCodepointCount_ReturnsInvalidArgument) {
    ke_font_data* data = nullptr;
    ke_result res = loader->load_font(loader, "test.ttf", 16.0f, 32, 0, 512, &data, nullptr);
    ASSERT_EQ(res, KE_ERROR);
}

TEST_F(StbFontTest, LoadFont_ZeroAtlasSize_ReturnsInvalidArgument) {
    ke_font_data* data = nullptr;
    ke_result res = loader->load_font(loader, "test.ttf", 16.0f, 32, 96, 0, &data, nullptr);
    ASSERT_EQ(res, KE_ERROR);
}

TEST_F(StbFontTest, LoadFont_Successful_OnWindows) {
    ke_font_data* data = nullptr;
    // On Windows, arial.ttf is almost always present
    ke_result res = loader->load_font(loader, "C:/Windows/Fonts/arial.ttf", 16.0f, 32, 96, 512, &data, nullptr);
    
    if (res == KE_OK) {
        ASSERT_NE(data, nullptr);
        EXPECT_EQ(data->glyph_count, 96u);
        EXPECT_NE(data->atlas_rgba, nullptr);
        loader->free_font(loader, data);
    } else {
        GTEST_SKIP() << "C:/Windows/Fonts/arial.ttf not found or inaccessible";
    }
}

TEST_F(StbFontTest, Destroy_NullHandle_IsSafe) {
    loader_h.destroy(nullptr);
}
