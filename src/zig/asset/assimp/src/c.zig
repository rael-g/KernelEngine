// Single @cImport for the plugin — separate blocks would produce distinct Zig
// types for the same C struct, so anything crossing between these files would
// stop typechecking.
//
// Assimp ships a C API (cimport.h) alongside its C++ one; this plugin uses the
// C API, so the module stays Zig end to end with no C++ toolchain involved.
// Everything else assimp exposes — aiScene, aiMesh, aiMaterial, aiTexture —
// is already a plain C struct.

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
