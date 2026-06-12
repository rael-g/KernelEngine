// Material TOML parser. Produces a plain ke_material_spec; texture paths are
// kept as strings so the caller (asset resolver) can resolve them through the
// image loading pipeline of its choice.

#include <kernel_engine/kernel/framework/material_file.h>
#include <toml++/toml.hpp>
#include <cstring>
#include <filesystem>

namespace fs = std::filesystem;

namespace
{

void copy_string(char *dest, const std::string &src, size_t cap)
{
    if (cap == 0) return;
    size_t len = src.size();
    if (len >= cap) len = cap - 1;
    std::memcpy(dest, src.data(), len);
    dest[len] = '\0';
}

void read_vec4(const toml::array &arr, float out[4])
{
    auto get = [&](size_t i) -> float {
        if (i >= arr.size()) return 0.0f;
        if (auto v = arr[i].value<double>()) return static_cast<float>(*v);
        if (auto v = arr[i].value<int64_t>()) return static_cast<float>(*v);
        return 0.0f;
    };
    out[0] = get(0); out[1] = get(1); out[2] = get(2); out[3] = get(3);
}

} // namespace

extern "C" ke_result ke_material_file_parse(const char *path, ke_material_spec *out_spec)
{
    if (!path || !out_spec) return KE_ERROR_INVALID_ARGUMENT;

    // Defaults: white, non-metallic, mid-roughness, no textures.
    out_spec->base_color[0] = 1.0f;
    out_spec->base_color[1] = 1.0f;
    out_spec->base_color[2] = 1.0f;
    out_spec->base_color[3] = 1.0f;
    out_spec->metallic       = 0.0f;
    out_spec->roughness      = 0.5f;
    out_spec->albedo_path[0] = '\0';
    out_spec->normal_path[0] = '\0';

    if (!fs::exists(path)) return KE_ERROR_NOT_FOUND;

    toml::table tbl;
    try {
        tbl = toml::parse_file(path);
    } catch (const toml::parse_error &) {
        return KE_ERROR_IO;
    }

    const auto *mat_tbl = tbl["material"].as_table();
    if (!mat_tbl) return KE_ERROR_INVALID_ARGUMENT;

    if (auto bc = (*mat_tbl)["base_color"].as_array()) read_vec4(*bc, out_spec->base_color);
    if (auto m  = (*mat_tbl)["metallic"].value<double>())  out_spec->metallic  = static_cast<float>(*m);
    if (auto r  = (*mat_tbl)["roughness"].value<double>()) out_spec->roughness = static_cast<float>(*r);
    if (auto a  = (*mat_tbl)["albedo"].value<std::string>()) copy_string(out_spec->albedo_path, *a, KE_MATERIAL_PATH_MAX);
    if (auto n  = (*mat_tbl)["normal"].value<std::string>()) copy_string(out_spec->normal_path, *n, KE_MATERIAL_PATH_MAX);

    return KE_OK;
}
