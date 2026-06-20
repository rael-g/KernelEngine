// ke_asset_resolver impl — pure C. Maps res:// / absolute / relative paths to
// CPU-side asset data via injected loaders (image_loader today; mesh loader
// slot reserved). Material parsing is an internal helper exposed only through
// the resolve_material vtable method (per the C-phase convention that the
// framework plugin's external surface is vtables + factories).

#include <kernel_engine/framework/asset_resolver_create.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>

#include "mesh_shape_internal.h"
#include "../third_party/tomlc99/toml.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Internal state ──────────────────────────────────────────────────────────

typedef struct asset_resolver_state {
    ke_asset_resolver  api;
    ke_image_loader   *image_loader;   // borrowed; may be NULL
    ke_font_loader    *font_loader;    // borrowed; may be NULL
    char              *project_root;   // owned (ke_alloc-allocated); may be NULL
} asset_resolver_state;

// ── Helpers ─────────────────────────────────────────────────────────────────

static char *dup_cstr(const char *s) {
    if (!s) return NULL;
    size_t n = strlen(s);
    char *out = (char *)ke_alloc(n + 1, 1);
    if (!out) return NULL;
    memcpy(out, s, n);
    out[n] = '\0';
    return out;
}

static bool file_exists(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    fclose(f);
    return true;
}

static void copy_string_clamped(char *dst, const char *src, size_t cap) {
    if (cap == 0) return;
    size_t n = strlen(src);
    if (n >= cap) n = cap - 1;
    memcpy(dst, src, n);
    dst[n] = '\0';
}

// Joins project_root and remainder into out_buf (size cap). Returns the number
// of bytes written excluding the NUL, or cap-1 on truncation. Inserts a '/'
// between root and remainder when neither side already supplies one.
static size_t join_path(char *out_buf, size_t cap, const char *root, const char *remainder) {
    if (cap == 0) return 0;
    size_t rlen = strlen(root);
    bool   need_sep = rlen > 0 && root[rlen - 1] != '/' && root[rlen - 1] != '\\'
                                 && remainder[0] != '/' && remainder[0] != '\\';
    size_t need = rlen + (need_sep ? 1 : 0) + strlen(remainder);
    if (need >= cap) need = cap - 1;

    size_t i = 0;
    for (size_t j = 0; j < rlen && i < cap - 1; ++j, ++i) out_buf[i] = root[j];
    if (need_sep && i < cap - 1) out_buf[i++] = '/';
    for (size_t j = 0; remainder[j] && i < cap - 1; ++j, ++i) out_buf[i] = remainder[j];
    out_buf[i] = '\0';
    return i;
}

// res://x → project_root/x ; else returned as-is. Result written into out_buf.
#define RES_PREFIX     "res://"
#define RES_PREFIX_LEN 6
static void resolve_path(const asset_resolver_state *s, const char *path,
                          char *out_buf, size_t cap) {
    if (strncmp(path, RES_PREFIX, RES_PREFIX_LEN) == 0) {
        const char *remainder = path + RES_PREFIX_LEN;
        if (s->project_root) {
            join_path(out_buf, cap, s->project_root, remainder);
        } else {
            copy_string_clamped(out_buf, remainder, cap);
        }
        return;
    }
    copy_string_clamped(out_buf, path, cap);
}

// ── Internal material parser ────────────────────────────────────────────────

// Parses a `.material` TOML file. Defaults applied for missing keys. Returns
// false on missing/unparseable file or absent [material] section.
//
// This function is intentionally NOT exposed in any public header. The
// framework plugin's only callable path to material specs is via
// ke_asset_resolver->resolve_material — convention §17.1.3 (plugins export
// vtable methods + factories, nothing else).
static bool parse_material_file(const char *path, ke_material_spec *out_spec) {
    if (!path || !out_spec) return false;

    // Defaults: white, non-metallic, mid-roughness, no textures.
    out_spec->base_color[0] = 1.0f;
    out_spec->base_color[1] = 1.0f;
    out_spec->base_color[2] = 1.0f;
    out_spec->base_color[3] = 1.0f;
    out_spec->metallic       = 0.0f;
    out_spec->roughness      = 0.5f;
    out_spec->albedo_path[0] = '\0';
    out_spec->normal_path[0] = '\0';

    FILE *fp = fopen(path, "rb");
    if (!fp) return false;

    char errbuf[200];
    toml_table_t *root = toml_parse_file(fp, errbuf, sizeof(errbuf));
    fclose(fp);
    if (!root) return false;

    toml_table_t *mat = toml_table_in(root, "material");
    if (!mat) { toml_free(root); return false; }

    toml_array_t *bc = toml_array_in(mat, "base_color");
    if (bc) {
        for (int i = 0; i < 4; ++i) {
            toml_datum_t v = toml_double_at(bc, i);
            if (v.ok) {
                out_spec->base_color[i] = (float)v.u.d;
                continue;
            }
            // Accept integers (e.g. base_color = [1, 1, 1, 1]) for ergonomics.
            toml_datum_t vi = toml_int_at(bc, i);
            if (vi.ok) out_spec->base_color[i] = (float)vi.u.i;
        }
    }

    toml_datum_t m = toml_double_in(mat, "metallic");
    if (m.ok) out_spec->metallic = (float)m.u.d;
    else {
        toml_datum_t mi = toml_int_in(mat, "metallic");
        if (mi.ok) out_spec->metallic = (float)mi.u.i;
    }

    toml_datum_t r = toml_double_in(mat, "roughness");
    if (r.ok) out_spec->roughness = (float)r.u.d;
    else {
        toml_datum_t ri = toml_int_in(mat, "roughness");
        if (ri.ok) out_spec->roughness = (float)ri.u.i;
    }

    toml_datum_t a = toml_string_in(mat, "albedo");
    if (a.ok) {
        copy_string_clamped(out_spec->albedo_path, a.u.s, KE_MATERIAL_PATH_MAX);
        free(a.u.s);
    }
    toml_datum_t n = toml_string_in(mat, "normal");
    if (n.ok) {
        copy_string_clamped(out_spec->normal_path, n.u.s, KE_MATERIAL_PATH_MAX);
        free(n.u.s);
    }

    toml_free(root);
    return true;
}

// ── Vtable methods ──────────────────────────────────────────────────────────

static bool vt_resolve_texture(ke_asset_resolver *self, const char *path,
                                     ke_texture_data **out, ke_error **out_error) {
    if (!self || !self->handle || !path || !out) {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return false;
    }
    asset_resolver_state *s = (asset_resolver_state *)self->handle;
    if (!s->image_loader) {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "no image loader injected");
        return false;
    }

    char buf[1024];
    resolve_path(s, path, buf, sizeof(buf));
    if (!file_exists(buf)) {
        KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "texture file not found");
        return false;
    }

    *out = s->image_loader->load_image(s->image_loader, buf, out_error);
    return *out != NULL;
}

static void vt_free_texture(ke_asset_resolver *self, ke_texture_data *data) {
    if (!self || !self->handle || !data) return;
    asset_resolver_state *s = (asset_resolver_state *)self->handle;
    if (s->image_loader && s->image_loader->free_image) {
        s->image_loader->free_image(s->image_loader, data);
    }
}

#define PRIMITIVE_PREFIX     "res://primitives/"
#define PRIMITIVE_PREFIX_LEN 17

static bool vt_resolve_mesh(ke_asset_resolver *self, const char *path,
                                  ke_mesh_shape_data *out, ke_error **out_error) {
    if (!self || !self->handle || !path || !out) {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return false;
    }
    asset_resolver_state *s = (asset_resolver_state *)self->handle;

    if (strncmp(path, PRIMITIVE_PREFIX, PRIMITIVE_PREFIX_LEN) == 0) {
        const char *name = path + PRIMITIVE_PREFIX_LEN;
        ke_mesh_primitive kind;
        if      (strcmp(name, "quad")   == 0) kind = KE_MESH_PRIMITIVE_QUAD;
        else if (strcmp(name, "plane")  == 0) kind = KE_MESH_PRIMITIVE_PLANE;
        else if (strcmp(name, "cube")   == 0) kind = KE_MESH_PRIMITIVE_CUBE;
        else if (strcmp(name, "sphere") == 0) kind = KE_MESH_PRIMITIVE_SPHERE;
        else {
            KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "unknown primitive");
            return false;
        }
        return ke_mesh_shape_bake_internal(kind, 0, out);
    }
    // Future: dispatch .gltf/.fbx/.obj via an injected ke_asset_loader.
    KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "mesh not found");
    return false;
}

static void vt_free_mesh(ke_asset_resolver *self, ke_mesh_shape_data *data) {
    if (!self || !self->handle || !data) return;
    asset_resolver_state *s = (asset_resolver_state *)self->handle;
    ke_mesh_shape_free_internal(data);
}

static bool vt_resolve_material(ke_asset_resolver *self, const char *path,
                                      ke_material_spec *out, ke_error **out_error) {
    if (!self || !self->handle || !path || !out) {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return false;
    }
    asset_resolver_state *s = (asset_resolver_state *)self->handle;
    char buf[1024];
    resolve_path(s, path, buf, sizeof(buf));
    if (!parse_material_file(buf, out)) {
        KE_ERROR_SET(out_error, &KE_ERROR_IO, "failed to parse material file");
        return false;
    }
    return true;
}

static bool vt_resolve_font(ke_asset_resolver *self, const char *path,
                                  float pixel_size, uint32_t first_codepoint,
                                  uint32_t codepoint_count, uint32_t atlas_size,
                                  ke_font_data **out, ke_error **out_error) {
    if (!self || !self->handle || !path || !out) {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return false;
    }
    asset_resolver_state *s = (asset_resolver_state *)self->handle;
    if (!s->font_loader) {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "no font loader injected");
        return false;
    }

    char buf[1024];
    resolve_path(s, path, buf, sizeof(buf));
    if (!file_exists(buf)) {
        KE_ERROR_SET(out_error, &KE_ERROR_NOT_FOUND, "font file not found");
        return false;
    }

    *out = s->font_loader->load_font(s->font_loader, buf, pixel_size,
                                     first_codepoint, codepoint_count,
                                     atlas_size, out_error);
    return *out != NULL;
}

static void vt_free_font(ke_asset_resolver *self, ke_font_data *data) {
    if (!self || !self->handle || !data) return;
    asset_resolver_state *s = (asset_resolver_state *)self->handle;
    if (s->font_loader && s->font_loader->free_font)
        s->font_loader->free_font(s->font_loader, data);
}

static void vt_destroy(ke_asset_resolver *self) {
    if (!self || !self->handle) return;
    asset_resolver_state *s = (asset_resolver_state *)self->handle;
    if (s->project_root) ke_free(s->project_root);
    ke_free(s);
}

// ── Factory ─────────────────────────────────────────────────────────────────

ke_asset_resolver_handle ke_asset_resolver_create(ke_image_loader *image_loader,
                                    ke_font_loader *font_loader,
                                    const char *project_root,
                                    ke_error **out_error) {
    ke_asset_resolver_handle null_handle = {0};

    asset_resolver_state *s = (asset_resolver_state *)ke_alloc(sizeof(asset_resolver_state), 8);
    if (!s) {
        KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "state allocation failed");
        return null_handle;
    }
    memset(s, 0, sizeof(*s));

    s->image_loader = image_loader;
    s->font_loader  = font_loader;
    s->project_root = dup_cstr(project_root);
    if (project_root && !s->project_root) {
        ke_free(s);
        KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "project root allocation failed");
        return null_handle;
    }

    s->api.handle           = s;
    s->api.resolve_texture  = vt_resolve_texture;
    s->api.free_texture     = vt_free_texture;
    s->api.resolve_mesh     = vt_resolve_mesh;
    s->api.free_mesh        = vt_free_mesh;
    s->api.resolve_material = vt_resolve_material;
    s->api.resolve_font     = vt_resolve_font;
    s->api.free_font        = vt_free_font;

    ke_asset_resolver_handle out;
    out.ref     = &s->api;
    out.destroy = vt_destroy;
    return out;
}
