#include <stddef.h>
#include <kernel_engine/render/material_file.h>
const unsigned long long layout_values[] = {
    sizeof(ke_material_spec),
    offsetof(ke_material_spec, base_color),
    offsetof(ke_material_spec, metallic),
    offsetof(ke_material_spec, roughness),
    offsetof(ke_material_spec, albedo_path),
    offsetof(ke_material_spec, normal_path),
    offsetof(ke_material_spec, alpha_mode),
    offsetof(ke_material_spec, alpha_cutoff),
    offsetof(ke_material_spec, ior),
    offsetof(ke_material_spec, distortion_strength),
    0,
};
