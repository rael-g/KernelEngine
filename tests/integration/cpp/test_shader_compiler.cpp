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
        compiler_h = ke_shader_compiler_bgfx_create(&params);
        compiler = compiler_h.ref;
    }

    void TearDown() override {
        if (compiler_h.ref) compiler_h.destroy(compiler_h.ref);
    }
};

// --- Creation Tests ---

TEST(ShaderCompilerInitTest, Create_NullParams_ReturnsNull) {
    ke_shader_compiler_handle c = ke_shader_compiler_bgfx_create(nullptr);
    ASSERT_EQ(c.ref, nullptr);
}

TEST(ShaderCompilerInitTest, Create_NullShadercPath_ReturnsNull) {
    ke_shader_compiler_bgfx_params params = { nullptr, nullptr };
    ke_shader_compiler_handle c = ke_shader_compiler_bgfx_create(&params);
    ASSERT_EQ(c.ref, nullptr);
}

// --- Lifecycle Tests ---

TEST_F(ShaderCompilerTest, ToApi_ReturnsValidPointer) {
    ASSERT_NE(compiler, nullptr);
}

TEST_F(ShaderCompilerTest, Handle_IsSet) {
    ASSERT_NE(compiler->handle, nullptr);
}

TEST_F(ShaderCompilerTest, OnInitialize_ReturnsOk) {
    ASSERT_TRUE(compiler->on_initialize(compiler, NULL));
}

TEST_F(ShaderCompilerTest, OnShutdown_ReturnsOk) {
    ASSERT_TRUE(compiler->on_shutdown(compiler, NULL));
}

// --- Compilation Tests ---

TEST_F(ShaderCompilerTest, Compile_InvalidBinary_ReturnsError) {
    // system() will fail to find 'invalid_shaderc_executable'
    bool ok = compiler->compile_shader(compiler, "test.vert", "varying.def", "v", "windows", "vs_5_0", nullptr, 0, nullptr);
    ASSERT_FALSE(ok);
}

TEST(ShaderCompilerEmptyTest, Create_NullShadercPath_ReturnsNull) {
    ke_shader_compiler_bgfx_params params = { nullptr, nullptr };
    ke_shader_compiler_handle ch = ke_shader_compiler_bgfx_create(&params);
    ASSERT_EQ(ch.ref, nullptr);
}

TEST_F(ShaderCompilerTest, Compile_WithIncludes_DoesNotCrash) {
    const char* includes[] = { "inc1", "inc2" };
    bool ok = compiler->compile_shader(compiler, "test.vert", "varying.def", "v", "windows", "vs_5_0", includes, 2, nullptr);
    ASSERT_FALSE(ok);
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
