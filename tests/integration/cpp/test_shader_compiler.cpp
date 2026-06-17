#include <gtest/gtest.h>
#include <kernel_engine/render/bgfx_shader_compiler/bgfx_shader_compiler.h>
#include <kernel_engine/render/render.h>
#include <kernel_engine/allocator/allocator.h>

class ShaderCompilerTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_shader_compiler* compiler = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ke_shader_compiler_bgfx_params params = { 
            .allocator = alloc,
            .logger = nullptr,
            .shaderc_path = "invalid_shaderc_executable"
        };
        ke_shader_compiler_bgfx_create(&params, &compiler);
    }

    void TearDown() override {
        if (compiler) compiler->destroy(compiler);
        if (alloc) alloc->destroy(alloc);
    }
};

// --- Creation Tests ---

TEST(ShaderCompilerInitTest, Create_NullOut_ReturnsInvalidArgument) {
    ASSERT_EQ(ke_shader_compiler_bgfx_create(nullptr, nullptr), KE_ERROR);
}

TEST(ShaderCompilerInitTest, Create_NullParams_ReturnsInvalidArgument) {
    ke_shader_compiler* c = nullptr;
    ASSERT_EQ(ke_shader_compiler_bgfx_create(nullptr, &c), KE_ERROR);
}

TEST(ShaderCompilerInitTest, Create_NullAllocator_ReturnsInvalidArgument) {
    ke_shader_compiler* c = nullptr;
    ke_shader_compiler_bgfx_params params = { nullptr, nullptr, nullptr };
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

TEST(ShaderCompilerEmptyTest, Compile_EmptyPath_ReturnsNotInitialized) {
    ke_allocator* a = ke_allocator_malloc_create();
    ke_shader_compiler_bgfx_params params = { a, nullptr, nullptr }; // Null path -> empty string
    ke_shader_compiler* c = nullptr;
    ke_shader_compiler_bgfx_create(&params, &c);
    
    ke_result res = c->compile_shader(c, "test.vert", "varying.def", "v", "windows", "vs_5_0", nullptr, 0, nullptr);
    
    ASSERT_EQ(res, KE_ERROR);
    c->destroy(c);
    a->destroy(a);
}

TEST_F(ShaderCompilerTest, Compile_WithIncludes_DoesNotCrash) {
    const char* includes[] = { "inc1", "inc2" };
    // Should still return KE_ERROR because binary is invalid, but tests the include loop
    ke_result res = compiler->compile_shader(compiler, "test.vert", "varying.def", "v", "windows", "vs_5_0", includes, 2, nullptr);
    ASSERT_EQ(res, KE_ERROR);
}

// --- Destroy Tests ---

TEST_F(ShaderCompilerTest, Destroy_Works) {
    compiler->destroy(compiler);
    compiler = nullptr;
    SUCCEED();
}

TEST_F(ShaderCompilerTest, Destroy_NullSelf_DoesNotCrash) {
    auto destroy_fn = compiler->destroy;
    destroy_fn(nullptr);
    SUCCEED();
}
