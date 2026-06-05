#include <gtest/gtest.h>
#include <kernel_engine/text/stb_truetype/stb_font.h>
#include <kernel_engine/kernel/context/allocator.h>

class StbFontTest : public ::testing::Test {
protected:
    ke_allocator* allocator = nullptr;
    ke_font_loader* loader = nullptr;

    void SetUp() override {
        allocator = ke_allocator_malloc_create();
        ke_font_loader_stb_params params{};
        params.allocator = allocator;
        params.logger = nullptr;
        
        ke_result res = ke_font_loader_stb_create(&params, &loader);
        ASSERT_EQ(res, KE_OK);
        ASSERT_NE(loader, nullptr);
    }

    void TearDown() override {
        if (loader) {
            loader->destroy(loader);
        }
        if (allocator) {
            allocator->destroy(allocator);
        }
    }
};

TEST_F(StbFontTest, Create_Works) {
    ASSERT_NE(loader, nullptr);
}

TEST_F(StbFontTest, LoadFont_FailsOnInvalidFile) {
    ke_font_data* data = nullptr;
    ke_result res = loader->load_font(loader, "non_existent.ttf", 16.0f, 32, 96, 512, &data);
    ASSERT_NE(res, KE_OK);
}

TEST_F(StbFontTest, FreeFont_Null_DoesNotCrash) {
    loader->free_font(loader, nullptr);
}
