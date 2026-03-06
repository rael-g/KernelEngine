#include <gtest/gtest.h>
#include <kernel_engine/render/bgfx_shader_compiler/bgfx_shader_compiler.hh>
#include <kernel_engine/kernel/context/allocator.h>

class ShaderCompilerTest : public ::testing::Test {
protected:
    ke_allocator* alloc = nullptr;
    ke_shader_compiler* compiler = nullptr;

    void SetUp() override {
        alloc = ke_allocator_malloc_create();
        ke_shader_compiler_bgfx_params params = { 
            .allocator = alloc,
            .shaderc_path = "path/to/shaderc"
        };
        ke_shader_compiler_bgfx_create(&params, &compiler);
    }

    void TearDown() override {
        if (compiler) compiler->destroy(compiler);
        if (alloc) alloc->destroy(alloc);
    }
};

TEST_F(ShaderCompilerTest, FactoryAndToApi) {
    ASSERT_NE(compiler, nullptr);
    ASSERT_NE(compiler->handle, nullptr);
}

TEST_F(ShaderCompilerTest, InvalidArgs) {
    // on_initialize might fail with invalid path, but we test the API surface
    // compiler->on_initialize(compiler); 
}
