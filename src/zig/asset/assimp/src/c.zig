
pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/logger/logger.h");
    @cInclude("kernel_engine/asset/asset_loader.h");
    @cInclude("kernel_engine/asset/assimp/assimp_loader.h");
    @cInclude("assimp/cimport.h");
    @cInclude("assimp/scene.h");
    @cInclude("assimp/mesh.h");
    @cInclude("assimp/material.h");
    @cInclude("assimp/texture.h");
    @cInclude("assimp/postprocess.h");
    @cInclude("stb_image.h");
});
