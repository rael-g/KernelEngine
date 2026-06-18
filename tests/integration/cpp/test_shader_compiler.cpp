#include <gtest/gtest.h>
#include <kernel_engine/render/bgfx_shader_compiler/bgfx_shader_compiler.h>
#include <kernel_engine/render/render.h>

class ShaderCompilerTest : public ::testing::Test {
protected:
    ke_shader_compiler_handle compiler_h{};
    ke_shader_compiler* compiler = nullptr;

    void SetUp() override {
        ke_shader_compiler_bgfx_params params = {
            .logger = nullptr,
            .shaderc_path = "invalid_shaderc_executable"
        };
        ke_shader_compiler_bgfx_create(&params, &compiler_h);
        compiler = compiler_h.ref;
    }

    void TearDown() override {
        if (compiler_h.ref) compiler_h.destroy(compiler_h.ref);
    }
};

// --- Creation Tests ---

TEST(ShaderCompilerInitTest, Create_NullOut_ReturnsInvalidArgument) {
    ASSERT_EQ(ke_shader_compiler_bgfx_create(nullptr, nullptr), KE_ERROR);
}

TEST(ShaderCompilerInitTest, Create_NullParams_ReturnsInvalidArgument) {
    ke_shader_compiler_handle c{};
    ASSERT_EQ(ke_shader_compiler_bgfx_create(nullptr, &c), KE_ERROR);
}

TEST(ShaderCompilerInitTest, Create_NullParams_Fields_ReturnsError) {
    ke_shader_compiler_handle c{};
    ke_shader_compiler_bgfx_params params = { nullptr, nullptr };
    ASSERT_EQ(ke_shader_compiler_bgfx_create(&params, &c), KE_ERROR);
}

// --- Lifecycle Tests ---

TEST_F(ShaderCompilerTest, ToApi_ReturnsValidPointer) {
    ASSERT_NE(compiler, nullptr);
}

TEST_F(ShaderCompilerTest, Handle_IsSet) {
    ASSERT_NE(compiler->handle, nullptr);
}

TEST_F(ShaderCompilerTest, OnInitialize_ReturnsOk) {
    ASSERT_EQ(compiler->on_initialize(compiler, NULL), KE_OK);
}

TEST_F(ShaderCompilerTest, OnShutdown_ReturnsOk) {
    ASSERT_EQ(compiler->on_shutdown(compiler, NULL), KE_OK);
}

// --- Compilation Tests ---

TEST_F(ShaderCompilerTest, Compile_InvalidBinary_ReturnsRenderError) {
    // system() will fail to find 'invalid_shaderc_executable'
    ke_result res = compiler->compile_shader(compiler, "test.vert", "varying.def", "v", "windows", "vs_5_0", nullptr, 0, nullptr);
    ASSERT_EQ(res, KE_ERROR);
}

TEST(ShaderCompilerEmptyTest, Create_NullShadercPath_ReturnsError) {
    ke_shader_compiler_bgfx_params params = { nullptr, nullptr };
    ke_shader_compiler_handle ch{};
    ASSERT_EQ(ke_shader_compiler_bgfx_create(&params, &ch), KE_ERROR);
    ASSERT_EQ(ch.ref, nullptr);
}

TEST_F(ShaderCompilerTest, Compile_WithIncludes_DoesNotCrash) {
    const char* includes[] = { "inc1", "inc2" };
    // Should still return KE_ERROR because binary is invalid, but tests the include loop
    ke_result res = compiler->compile_shader(compiler, "test.vert", "varying.def", "v", "windows", "vs_5_0", includes, 2, nullptr);
    ASSERT_EQ(res, KE_ERROR);
}

// --- Destroy Tests ---

TEST_F(ShaderCompilerTest, Destroy_Works) {
    compiler_h.destroy(compiler_h.ref);
    compiler = nullptr;
    compiler_h = {};
    SUCCEED();
}

TEST_F(ShaderCompilerTest, Destroy_NullSelf_DoesNotCrash) {
    auto destroy_fn = compiler_h.destroy;
    destroy_fn(nullptr);
    SUCCEED();
}
