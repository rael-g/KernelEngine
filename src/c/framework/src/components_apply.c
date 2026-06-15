// Per-component apply callbacks for the framework's component vocabulary.
// Each one translates a variant-table entry list into the matching component's
// raw memory. Game code can register apply callbacks for its own components
// via world->register_component_apply.
//
// Conventions:
//   - Field name matching is case-sensitive and exact ("color" != "Color").
//   - Type mismatches are silently skipped (loader semantics: unknown ↔ ignore).
//   - Vec arrays from TOML come pre-converted to KE_VARIANT_VEC2/VEC3/VEC4 by
//     the scene_loader's toml→variant pass. A 3-element array becomes VEC3;
//     applies decide whether they want VEC3 or VEC4.

#include "components_apply.h"

#include <kernel_engine/framework/components.h>

#include <math.h>
#include <stdbool.h>
#include <string.h>

static const float kPi = 3.14159265358979323846f;

// Euler ZYX intrinsic, degrees in → quaternion. Mirrors the cpp impl that
// matched C# SceneLoader's CreateFromYawPitchRoll(yaw=y, pitch=x, roll=z).
static ke_quat euler_deg_to_quat(float dx, float dy, float dz) {
    const float k = kPi / 180.0f * 0.5f;
    float x = dx * k, y = dy * k, z = dz * k;
    float cx = cosf(x), sx = sinf(x);
    float cy = cosf(y), sy = sinf(y);
    float cz = cosf(z), sz = sinf(z);
    ke_quat q;
    q.x = sx * cy * cz - cx * sy * sz;
    q.y = cx * sy * cz + sx * cy * sz;
    q.z = cx * cy * sz - sx * sy * cz;
    q.w = cx * cy * cz + sx * sy * sz;
    return q;
}

static bool as_float(const ke_variant *v, float *out) {
    if (v->type == KE_VARIANT_FLOAT) { *out = (float)v->f; return true; }
    if (v->type == KE_VARIANT_INT)   { *out = (float)v->i; return true; }
    return false;
}

// ── transform ───────────────────────────────────────────────────────────────

void ke_framework_apply_transform(void *c, const ke_variant_table_entry *e, uint32_t n) {
    ke_transform_component *t = (ke_transform_component *)c;
    for (uint32_t i = 0; i < n; ++i) {
        const ke_variant *v = &e[i].value;
        if (strcmp(e[i].key, "position") == 0) {
            if (v->type == KE_VARIANT_VEC3) t->position = v->v3;
            else if (v->type == KE_VARIANT_VEC2) { t->position.x = v->v2.x; t->position.y = v->v2.y; t->position.z = 0; }
        } else if (strcmp(e[i].key, "scale") == 0) {
            if (v->type == KE_VARIANT_VEC3) t->scale = v->v3;
            else if (v->type == KE_VARIANT_VEC2) { t->scale.x = v->v2.x; t->scale.y = v->v2.y; t->scale.z = 1; }
        } else if (strcmp(e[i].key, "rotation") == 0) {
            if (v->type == KE_VARIANT_VEC4) {
                t->rotation.x = v->v4.x; t->rotation.y = v->v4.y;
                t->rotation.z = v->v4.z; t->rotation.w = v->v4.w;
            } else if (v->type == KE_VARIANT_QUAT) {
                t->rotation = v->q;
            }
        } else if (strcmp(e[i].key, "rotation_euler") == 0) {
            if (v->type == KE_VARIANT_VEC3) {
                t->rotation = euler_deg_to_quat(v->v3.x, v->v3.y, v->v3.z);
            }
        }
    }
}

// ── camera ──────────────────────────────────────────────────────────────────

void ke_framework_apply_camera(void *c, const ke_variant_table_entry *e, uint32_t n) {
    ke_camera_component *cam = (ke_camera_component *)c;
    for (uint32_t i = 0; i < n; ++i) {
        const ke_variant *v = &e[i].value;
        float f;
        if (strcmp(e[i].key, "fov") == 0 && as_float(v, &f)) {
            cam->fov = f;
        } else if (strcmp(e[i].key, "fov_degrees") == 0 && as_float(v, &f)) {
            // Convenient alias: scene file says degrees, component stores radians.
            cam->fov = f * (kPi / 180.0f);
        } else if (strcmp(e[i].key, "near_plane") == 0 && as_float(v, &f)) {
            cam->near_plane = f;
        } else if (strcmp(e[i].key, "far_plane") == 0 && as_float(v, &f)) {
            cam->far_plane = f;
        } else if (strcmp(e[i].key, "orthographic_size") == 0 && as_float(v, &f)) {
            cam->orthographic_size = f;
        } else if (strcmp(e[i].key, "orthographic") == 0) {
            if (v->type == KE_VARIANT_BOOL) cam->orthographic = v->b ? 1 : 0;
            else if (v->type == KE_VARIANT_INT) cam->orthographic = (uint8_t)(v->i ? 1 : 0);
        }
    }
}

// ── mesh ────────────────────────────────────────────────────────────────────

void ke_framework_apply_mesh(void *c, const ke_variant_table_entry *e, uint32_t n) {
    ke_mesh_component *m = (ke_mesh_component *)c;
    for (uint32_t i = 0; i < n; ++i) {
        const ke_variant *v = &e[i].value;
        if (strcmp(e[i].key, "primitive") == 0 && v->type == KE_VARIANT_STRING && v->s) {
            size_t len = strlen(v->s);
            if (len >= sizeof(m->primitive)) len = sizeof(m->primitive) - 1;
            memcpy(m->primitive, v->s, len);
            m->primitive[len] = '\0';
        } else if (strcmp(e[i].key, "color") == 0) {
            if (v->type == KE_VARIANT_VEC4) {
                m->color[0] = v->v4.x; m->color[1] = v->v4.y;
                m->color[2] = v->v4.z; m->color[3] = v->v4.w;
            } else if (v->type == KE_VARIANT_VEC3) {
                m->color[0] = v->v3.x; m->color[1] = v->v3.y;
                m->color[2] = v->v3.z; m->color[3] = 1.0f;
            }
        }
    }
}

// ── directional light ──────────────────────────────────────────────────────

void ke_framework_apply_directional_light(void *c, const ke_variant_table_entry *e, uint32_t n) {
    ke_directional_light_component *l = (ke_directional_light_component *)c;
    for (uint32_t i = 0; i < n; ++i) {
        const ke_variant *v = &e[i].value;
        float f;
        if (strcmp(e[i].key, "direction") == 0 && v->type == KE_VARIANT_VEC3) {
            l->dir_x = v->v3.x; l->dir_y = v->v3.y; l->dir_z = v->v3.z;
        } else if (strcmp(e[i].key, "color") == 0 && v->type == KE_VARIANT_VEC3) {
            l->r = v->v3.x; l->g = v->v3.y; l->b = v->v3.z;
        } else if (strcmp(e[i].key, "intensity") == 0 && as_float(v, &f)) {
            l->intensity = f;
        } else if (strcmp(e[i].key, "dir_x") == 0 && as_float(v, &f)) { l->dir_x = f; }
          else if (strcmp(e[i].key, "dir_y") == 0 && as_float(v, &f)) { l->dir_y = f; }
          else if (strcmp(e[i].key, "dir_z") == 0 && as_float(v, &f)) { l->dir_z = f; }
          else if (strcmp(e[i].key, "r") == 0 && as_float(v, &f)) { l->r = f; }
          else if (strcmp(e[i].key, "g") == 0 && as_float(v, &f)) { l->g = f; }
          else if (strcmp(e[i].key, "b") == 0 && as_float(v, &f)) { l->b = f; }
    }
}

// ── point light ────────────────────────────────────────────────────────────

void ke_framework_apply_point_light(void *c, const ke_variant_table_entry *e, uint32_t n) {
    ke_point_light_component *l = (ke_point_light_component *)c;
    for (uint32_t i = 0; i < n; ++i) {
        const ke_variant *v = &e[i].value;
        float f;
        if (strcmp(e[i].key, "color") == 0 && v->type == KE_VARIANT_VEC3) {
            l->r = v->v3.x; l->g = v->v3.y; l->b = v->v3.z;
        } else if (strcmp(e[i].key, "radius") == 0 && as_float(v, &f)) { l->radius = f; }
          else if (strcmp(e[i].key, "intensity") == 0 && as_float(v, &f)) { l->intensity = f; }
          else if (strcmp(e[i].key, "r") == 0 && as_float(v, &f)) { l->r = f; }
          else if (strcmp(e[i].key, "g") == 0 && as_float(v, &f)) { l->g = f; }
          else if (strcmp(e[i].key, "b") == 0 && as_float(v, &f)) { l->b = f; }
    }
}

// ── spot light ─────────────────────────────────────────────────────────────

void ke_framework_apply_spot_light(void *c, const ke_variant_table_entry *e, uint32_t n) {
    ke_spot_light_component *l = (ke_spot_light_component *)c;
    for (uint32_t i = 0; i < n; ++i) {
        const ke_variant *v = &e[i].value;
        float f;
        if (strcmp(e[i].key, "direction") == 0 && v->type == KE_VARIANT_VEC3) {
            l->dir_x = v->v3.x; l->dir_y = v->v3.y; l->dir_z = v->v3.z;
        } else if (strcmp(e[i].key, "color") == 0 && v->type == KE_VARIANT_VEC3) {
            l->r = v->v3.x; l->g = v->v3.y; l->b = v->v3.z;
        } else if (strcmp(e[i].key, "inner_angle") == 0 && as_float(v, &f)) { l->inner_angle = f; }
          else if (strcmp(e[i].key, "outer_angle") == 0 && as_float(v, &f)) { l->outer_angle = f; }
          else if (strcmp(e[i].key, "range") == 0 && as_float(v, &f)) { l->range = f; }
          else if (strcmp(e[i].key, "intensity") == 0 && as_float(v, &f)) { l->intensity = f; }
          else if (strcmp(e[i].key, "dir_x") == 0 && as_float(v, &f)) { l->dir_x = f; }
          else if (strcmp(e[i].key, "dir_y") == 0 && as_float(v, &f)) { l->dir_y = f; }
          else if (strcmp(e[i].key, "dir_z") == 0 && as_float(v, &f)) { l->dir_z = f; }
          else if (strcmp(e[i].key, "r") == 0 && as_float(v, &f)) { l->r = f; }
          else if (strcmp(e[i].key, "g") == 0 && as_float(v, &f)) { l->g = f; }
          else if (strcmp(e[i].key, "b") == 0 && as_float(v, &f)) { l->b = f; }
    }
}
