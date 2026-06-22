#include <kernel_engine/common/error.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu_device.h>
#include <kernel_engine/render/gpu_commands.h>
#include <kernel_engine/render/gpu_enums.h>
#include <kernel_engine/render/gpu_surface_ext.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>

#include "tex_vert.h"
#include "tex_frag.h"

#include <stdint.h>
#include <stdio.h>

static void die(const char *msg, ke_error *err)
{
    if (err)
        fprintf(stderr, "ERROR [%s]: %s\n", err->type->name, err->message);
    else
        fprintf(stderr, "ERROR: %s\n", msg);
    __builtin_trap();
}

typedef struct { float x, y, u, v; } vertex_t;

static const vertex_t vertices[] = {
    { -0.75f, -0.75f,  0.0f, 0.0f },
    {  0.75f, -0.75f,  1.0f, 0.0f },
    {  0.75f,  0.75f,  1.0f, 1.0f },
    { -0.75f,  0.75f,  0.0f, 1.0f },
};
static const uint16_t indices[] = { 0, 1, 2, 0, 2, 3 };

#define TEX_SIZE 64

static void make_checkerboard(uint8_t *out, int size, int cell)
{
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            int on = ((x / cell) + (y / cell)) % 2;
            uint8_t *p = out + (y * size + x) * 4;
            p[0] = on ? 255 : 64;
            p[1] = on ? 255 : 64;
            p[2] = on ? 255 : 64;
            p[3] = 255;
        }
    }
}

int main(void)
{
    printf("--- c_demo_09: textured quad ---\n");

    ke_error *err = NULL;

    // ── Window ───────────────────────────────────────────────────────────────

    ke_window_glfw_params wp = {
        .logger     = NULL,
        .input      = NULL,
        .title      = "c_demo_09 texture",
        .width      = 800,
        .height     = 600,
        .fullscreen = false,
    };
    ke_window_handle win = ke_window_glfw_create(&wp, &err);
    if (!win.ref) die("window create failed", err);
    if (!win.ref->on_initialize(win.ref, &err)) die("window init failed", err);

    // ── GPU device ────────────────────────────────────────────────────────────

    ke_gpu_device_webgpu_params dp = {
        .logger            = NULL,
        .window            = win.ref,
        .enable_validation = 1,
    };
    ke_gpu_device_handle gpu = ke_gpu_device_webgpu_create(&dp, &err);
    if (!gpu.ref) die("gpu device create failed", err);

    const ke_gpu_surface_ext *surf_ext =
        (const ke_gpu_surface_ext *)gpu.ref->query_extension(gpu.ref, KE_GPU_SURFACE_EXT_NAME);
    if (!surf_ext) die("surface extension not available", NULL);

    // ── Checkerboard texture ──────────────────────────────────────────────────

    static uint8_t pixels[TEX_SIZE * TEX_SIZE * 4];
    make_checkerboard(pixels, TEX_SIZE, 8);

    ke_gpu_texture_params tp = {
        .width                = TEX_SIZE,
        .height               = TEX_SIZE,
        .depth_or_array_layers = 1,
        .format               = KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension            = KE_GPU_TEXTURE_DIM_2D,
        .usage                = KE_GPU_TEXTURE_USAGE_SAMPLED,
        .mip_level_count      = 1,
        .sample_count         = 1,
        .initial_data         = pixels,
        .initial_data_size    = sizeof(pixels),
    };
    ke_gpu_texture tex = gpu.ref->create_texture(gpu.ref, &tp);
    if (tex == KE_GPU_INVALID_HANDLE) die("texture creation failed", NULL);

    ke_gpu_texture_view_params tvp = {
        .format          = KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension       = KE_GPU_TEXTURE_DIM_2D,
        .aspect          = KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level  = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
    };
    ke_gpu_texture_view tex_view = gpu.ref->create_texture_view(gpu.ref, tex, &tvp);
    if (tex_view == KE_GPU_INVALID_HANDLE) die("texture view creation failed", NULL);

    // ── Sampler ───────────────────────────────────────────────────────────────

    ke_gpu_sampler_params sp = {
        .address_mode_u = KE_GPU_ADDRESS_MODE_REPEAT,
        .address_mode_v = KE_GPU_ADDRESS_MODE_REPEAT,
        .address_mode_w = KE_GPU_ADDRESS_MODE_REPEAT,
        .mag_filter     = KE_GPU_FILTER_LINEAR,
        .min_filter     = KE_GPU_FILTER_LINEAR,
        .mipmap_filter  = KE_GPU_FILTER_NEAREST,
        .lod_min_clamp  = 0.0f,
        .lod_max_clamp  = 1.0f,
        .compare        = KE_GPU_COMPARE_UNDEFINED,
        .max_anisotropy = 1,
    };
    ke_gpu_sampler sampler = gpu.ref->create_sampler(gpu.ref, &sp);
    if (sampler == KE_GPU_INVALID_HANDLE) die("sampler creation failed", NULL);

    // ── Bind group layout: sampler2D at binding 0 ─────────────────────────────
    // WebGPU separates texture and sampler into two bindings.

    ke_gpu_bind_group_layout_entry bgl_entries[2] = {
        { .binding = 0, .visibility = KE_GPU_SHADER_STAGE_FRAGMENT, .type = KE_GPU_BINDING_TYPE_TEXTURE },
        { .binding = 1, .visibility = KE_GPU_SHADER_STAGE_FRAGMENT, .type = KE_GPU_BINDING_TYPE_SAMPLER },
    };
    ke_gpu_bind_group_layout_params bgl_params = { .entry_count = 2, .entries = bgl_entries };
    ke_gpu_bind_group_layout bgl = gpu.ref->create_bind_group_layout(gpu.ref, &bgl_params);
    if (bgl == KE_GPU_INVALID_HANDLE) die("bind group layout creation failed", NULL);

    ke_gpu_bind_group_entry bg_entries[2] = {
        { .binding = 0, .type = KE_GPU_BINDING_TYPE_TEXTURE, .texture_view = tex_view },
        { .binding = 1, .type = KE_GPU_BINDING_TYPE_SAMPLER, .sampler      = sampler  },
    };
    ke_gpu_bind_group_params bg_params = { .layout = bgl, .entry_count = 2, .entries = bg_entries };
    ke_gpu_bind_group bg = gpu.ref->create_bind_group(gpu.ref, &bg_params);
    if (bg == KE_GPU_INVALID_HANDLE) die("bind group creation failed", NULL);

    // ── Geometry ──────────────────────────────────────────────────────────────

    ke_gpu_buffer vbo = gpu.ref->create_buffer(gpu.ref, &(ke_gpu_buffer_params){
        .initial_data = vertices, .size = sizeof(vertices),
        .usage = KE_GPU_BUFFER_USAGE_VERTEX,
    });
    ke_gpu_buffer ibo = gpu.ref->create_buffer(gpu.ref, &(ke_gpu_buffer_params){
        .initial_data = indices, .size = sizeof(indices),
        .usage = KE_GPU_BUFFER_USAGE_INDEX,
    });

    // ── Shaders ───────────────────────────────────────────────────────────────

    ke_gpu_shader_module vs = gpu.ref->create_shader_module(gpu.ref, &(ke_gpu_shader_module_params){
        .code = tex_vert_spv, .byte_size = sizeof(tex_vert_spv), .entry_point = "main",
    });
    ke_gpu_shader_module fs = gpu.ref->create_shader_module(gpu.ref, &(ke_gpu_shader_module_params){
        .code = tex_frag_spv, .byte_size = sizeof(tex_frag_spv), .entry_point = "main",
    });

    // ── Pipeline ─────────────────────────────────────────────────────────────

    ke_gpu_vertex_attribute attrs[] = {
        { .shader_location = 0, .format = KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = 0 },
        { .shader_location = 1, .format = KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = sizeof(float) * 2 },
    };
    ke_gpu_vertex_buffer_layout vbl = {
        .stride = sizeof(vertex_t), .step_mode = KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 2, .attributes = attrs,
    };
    ke_gpu_render_pipeline_params pp = {
        .vertex_module = vs, .fragment_module = fs,
        .primitive_topology      = KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .cull_mode               = KE_GPU_CULL_MODE_NONE,
        .front_face              = KE_GPU_FRONT_FACE_CCW,
        .vertex_buffer_count     = 1, .vertex_buffers = &vbl,
        .blend_state             = { .blend_enabled = 0, .src_color = KE_GPU_BLEND_FACTOR_ONE,
                                     .dst_color = KE_GPU_BLEND_FACTOR_ZERO, .color_op = KE_GPU_BLEND_OP_ADD,
                                     .src_alpha = KE_GPU_BLEND_FACTOR_ONE, .dst_alpha = KE_GPU_BLEND_FACTOR_ZERO,
                                     .alpha_op = KE_GPU_BLEND_OP_ADD, .write_mask = 0x0F },
        .depth_stencil           = { .depth_test_enabled = 0 },
        .bind_group_layouts[0]   = bgl,
        .bind_group_layout_count = 1,
    };
    ke_gpu_pipeline pipeline = gpu.ref->create_render_pipeline(gpu.ref, &pp);
    if (pipeline == KE_GPU_INVALID_HANDLE) die("pipeline creation failed", NULL);

    gpu.ref->destroy_shader_module(gpu.ref, vs);
    gpu.ref->destroy_shader_module(gpu.ref, fs);

    ke_gpu_queue q = gpu.ref->get_default_queue(gpu.ref);

    // ── Loop ──────────────────────────────────────────────────────────────────

    printf("Rendering textured quad. Close the window to exit.\n");

    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref, NULL);

        ke_gpu_texture_view view = surf_ext->acquire_current_texture_view(surf_ext);
        if (view == KE_GPU_INVALID_HANDLE) continue;

        ke_gpu_color_attachment ca = {
            .view        = view,
            .load_op     = KE_GPU_LOAD_OP_CLEAR,
            .store_op    = KE_GPU_STORE_OP_STORE,
            .clear_value = { .color = { 0.05f, 0.05f, 0.1f, 1.0f } },
        };
        ke_gpu_render_pass_params rpp = {
            .color_attachments = &ca, .color_attachment_count = 1,
        };

        ke_gpu_command_encoder *enc = gpu.ref->create_command_encoder(gpu.ref);
        ke_gpu_render_pass *rp = enc->begin_render_pass(enc, &rpp);
        rp->set_pipeline(rp, pipeline);
        rp->set_bind_group(rp, 0, bg, NULL, 0);
        rp->set_vertex_buffer(rp, 0, vbo, 0);
        rp->set_index_buffer(rp, ibo, KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp->draw_indexed(rp, 6, 1, 0, 0, 0);
        rp->end(rp);

        ke_gpu_command_buffer *cmd = enc->finish(enc);
        enc->destroy(enc);
        ke_gpu_command_buffer *cmds[] = { cmd };
        gpu.ref->queue_submit(gpu.ref, q, cmds, 1);
        cmd->destroy(cmd);
        gpu.ref->queue_present(gpu.ref, q);
        gpu.ref->destroy_texture_view(gpu.ref, view);
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────

    gpu.ref->destroy_pipeline(gpu.ref, pipeline);
    gpu.ref->destroy_bind_group(gpu.ref, bg);
    gpu.ref->destroy_bind_group_layout(gpu.ref, bgl);
    gpu.ref->destroy_sampler(gpu.ref, sampler);
    gpu.ref->destroy_texture_view(gpu.ref, tex_view);
    gpu.ref->destroy_texture(gpu.ref, tex);
    gpu.ref->destroy_buffer(gpu.ref, ibo);
    gpu.ref->destroy_buffer(gpu.ref, vbo);
    gpu.destroy(gpu.ref);
    win.ref->on_shutdown(win.ref, NULL);
    win.destroy(win.ref);

    printf("--- Done ---\n");
    return 0;
}
