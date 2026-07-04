#include <kernel_engine/common/error.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu_device.h>
#include <kernel_engine/render/gpu_commands.h>
#include <kernel_engine/render/gpu_enums.h>
#include <kernel_engine/render/gpu_surface_ext.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>

#include "depth_vert.h"
#include "depth_frag.h"

#include <stdint.h>
#include <stdio.h>

static void die(const char *msg, ke_error *err)
{
    if (err) { ke_error_fatal(err); }
    ke_error fallback = { .type = &KE_ERROR_GENERAL, .message = msg, .file = __FILE__, .line = __LINE__, .cause = NULL };
    ke_error_fatal(&fallback);
}

// xyz + rgb
typedef struct { float x, y, z, r, g, b; } vertex_t;

// Back quad (z=0.5): red — should be occluded where the front quad overlaps
static const vertex_t back_verts[] = {
    { -0.6f, -0.6f, 0.5f,  1.0f, 0.2f, 0.2f },
    {  0.6f, -0.6f, 0.5f,  1.0f, 0.2f, 0.2f },
    {  0.6f,  0.6f, 0.5f,  1.0f, 0.2f, 0.2f },
    { -0.6f,  0.6f, 0.5f,  1.0f, 0.2f, 0.2f },
};

// Front quad (z=0.2): blue — should always win where it covers back quad
static const vertex_t front_verts[] = {
    { -0.4f, -0.4f, 0.2f,  0.2f, 0.4f, 1.0f },
    {  0.7f, -0.4f, 0.2f,  0.2f, 0.4f, 1.0f },
    {  0.7f,  0.4f, 0.2f,  0.2f, 0.4f, 1.0f },
    { -0.4f,  0.4f, 0.2f,  0.2f, 0.4f, 1.0f },
};

static const uint16_t quad_idx[] = { 0, 1, 2, 0, 2, 3 };

#define WIDTH  800
#define HEIGHT 600

int main(void)
{
    printf("--- c_demo_10: depth buffer ---\n");
    ke_error *err = NULL;

    ke_window_glfw_params wp = {
        .logger = NULL, .input = NULL,
        .title = "c_demo_10 depth", .width = WIDTH, .height = HEIGHT,
    };
    ke_window_handle win = ke_window_glfw_create(&wp, &err);
    if (!win.ref) die("window", err);
    if (!win.ref->on_initialize(win.ref, &err)) die("window init", err);

    ke_gpu_device_webgpu_params dp = { .logger = NULL, .window = win.ref, .enable_validation = 1 };
    ke_gpu_device_handle gpu = ke_gpu_device_webgpu_create(&dp, &err);
    if (!gpu.ref) die("gpu device", err);

    const ke_gpu_surface_ext *surf_ext =
        (const ke_gpu_surface_ext *)gpu.ref->query_extension(gpu.ref, KE_GPU_SURFACE_EXT_NAME);
    if (!surf_ext) die("surface ext", NULL);

    // ── Depth texture (recreated on resize; fixed size for this demo) ─────────

    ke_gpu_texture depth_tex = gpu.ref->create_texture(gpu.ref, &(ke_gpu_texture_params){
        .width = WIDTH, .height = HEIGHT, .depth_or_array_layers = 1,
        .format = KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .dimension = KE_GPU_TEXTURE_DIM_2D,
        .usage = KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH,
        .mip_level_count = 1, .sample_count = 1,
    });
    if (depth_tex == KE_GPU_INVALID_HANDLE) die("depth texture", NULL);

    ke_gpu_texture_view depth_view = gpu.ref->create_texture_view(gpu.ref, depth_tex,
        &(ke_gpu_texture_view_params){
            .format = KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
            .dimension = KE_GPU_TEXTURE_DIM_2D,
            .aspect = KE_GPU_TEXTURE_ASPECT_DEPTH,
            .mip_level_count = 1, .array_layer_count = 1,
        });
    if (depth_view == KE_GPU_INVALID_HANDLE) die("depth view", NULL);

    // ── Geometry ──────────────────────────────────────────────────────────────

    ke_gpu_buffer vbo_back  = gpu.ref->create_buffer(gpu.ref, &(ke_gpu_buffer_params){
        .initial_data = back_verts,  .size = sizeof(back_verts),  .usage = KE_GPU_BUFFER_USAGE_VERTEX }, &err);
    if (vbo_back == KE_GPU_INVALID_HANDLE) die("back vertex buffer creation failed", err);
    ke_gpu_buffer vbo_front = gpu.ref->create_buffer(gpu.ref, &(ke_gpu_buffer_params){
        .initial_data = front_verts, .size = sizeof(front_verts), .usage = KE_GPU_BUFFER_USAGE_VERTEX }, &err);
    if (vbo_front == KE_GPU_INVALID_HANDLE) die("front vertex buffer creation failed", err);
    ke_gpu_buffer ibo = gpu.ref->create_buffer(gpu.ref, &(ke_gpu_buffer_params){
        .initial_data = quad_idx, .size = sizeof(quad_idx), .usage = KE_GPU_BUFFER_USAGE_INDEX }, &err);
    if (ibo == KE_GPU_INVALID_HANDLE) die("index buffer creation failed", err);

    // ── Shaders ───────────────────────────────────────────────────────────────

    ke_gpu_shader_module vs = gpu.ref->create_shader_module(gpu.ref, &(ke_gpu_shader_module_params){
        .code = depth_vert_spv, .byte_size = sizeof(depth_vert_spv), .entry_point = "main" }, &err);
    ke_gpu_shader_module fs = gpu.ref->create_shader_module(gpu.ref, &(ke_gpu_shader_module_params){
        .code = depth_frag_spv, .byte_size = sizeof(depth_frag_spv), .entry_point = "main" }, &err);

    // ── Pipeline (depth write + less-or-equal test) ───────────────────────────

    ke_gpu_vertex_attribute attrs[] = {
        { .shader_location = 0, .format = KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 },
        { .shader_location = 1, .format = KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = sizeof(float) * 3 },
    };
    ke_gpu_vertex_buffer_layout vbl = {
        .stride = sizeof(vertex_t), .step_mode = KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 2, .attributes = attrs,
    };
    ke_gpu_render_pipeline_params pp = {
        .vertex_module = vs, .fragment_module = fs,
        .primitive_topology = KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .cull_mode = KE_GPU_CULL_MODE_NONE, .front_face = KE_GPU_FRONT_FACE_CCW,
        .vertex_buffer_count = 1, .vertex_buffers = &vbl,
        .blend_state = { .blend_enabled = 0, .src_color = KE_GPU_BLEND_FACTOR_ONE,
                         .dst_color = KE_GPU_BLEND_FACTOR_ZERO, .color_op = KE_GPU_BLEND_OP_ADD,
                         .src_alpha = KE_GPU_BLEND_FACTOR_ONE, .dst_alpha = KE_GPU_BLEND_FACTOR_ZERO,
                         .alpha_op = KE_GPU_BLEND_OP_ADD, .write_mask = 0x0F },
        .depth_stencil = {
            .depth_test_enabled  = 1,
            .depth_write_enabled = 1,
            .depth_compare       = KE_GPU_COMPARE_LESS_EQUAL,
        },
    };
    ke_gpu_pipeline pipeline = gpu.ref->create_render_pipeline(gpu.ref, &pp);
    if (pipeline == KE_GPU_INVALID_HANDLE) die("pipeline", NULL);

    gpu.ref->destroy_shader_module(gpu.ref, vs);
    gpu.ref->destroy_shader_module(gpu.ref, fs);

    ke_gpu_queue q = gpu.ref->get_default_queue(gpu.ref);

    printf("Rendering two overlapping quads with depth test. Close to exit.\n");
    printf("Blue quad (z=0.2) should appear in front of red quad (z=0.5).\n");

    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref, NULL);

        ke_gpu_texture_view color_view = surf_ext->acquire_current_texture_view(surf_ext);
        if (color_view == KE_GPU_INVALID_HANDLE) continue;

        ke_gpu_color_attachment ca = {
            .view = color_view, .load_op = KE_GPU_LOAD_OP_CLEAR, .store_op = KE_GPU_STORE_OP_STORE,
            .clear_value = { .color = { 0.05f, 0.05f, 0.08f, 1.0f } },
        };
        ke_gpu_depth_stencil_attachment dsa = {
            .view = depth_view,
            .depth_load_op = KE_GPU_LOAD_OP_CLEAR, .depth_store_op = KE_GPU_STORE_OP_STORE,
            .clear_depth = 1.0f,
            .stencil_store_op = KE_GPU_STORE_OP_DONT_CARE,
        };
        ke_gpu_render_pass_params rpp = {
            .color_attachments = &ca, .color_attachment_count = 1,
            .depth_stencil_attachment = &dsa,
        };

        ke_gpu_command_encoder *enc = gpu.ref->create_command_encoder(gpu.ref);
        ke_gpu_render_pass *rp = enc->begin_render_pass(enc, &rpp);
        rp->set_pipeline(rp, pipeline);
        rp->set_index_buffer(rp, ibo, KE_GPU_INDEX_FORMAT_UINT16, 0);

        // Draw back quad first (red, z=0.5)
        rp->set_vertex_buffer(rp, 0, vbo_back, 0);
        rp->draw_indexed(rp, 6, 1, 0, 0, 0);

        // Draw front quad (blue, z=0.2) — depth test ensures it wins
        rp->set_vertex_buffer(rp, 0, vbo_front, 0);
        rp->draw_indexed(rp, 6, 1, 0, 0, 0);

        rp->end(rp);

        ke_gpu_command_buffer *cmd = enc->finish(enc);
        enc->destroy(enc);
        ke_gpu_command_buffer *cmds[] = { cmd };
        gpu.ref->queue_submit(gpu.ref, q, cmds, 1);
        cmd->destroy(cmd);
        gpu.ref->queue_present(gpu.ref, q);
        gpu.ref->destroy_texture_view(gpu.ref, color_view);
    }

    gpu.ref->destroy_pipeline(gpu.ref, pipeline);
    gpu.ref->destroy_buffer(gpu.ref, ibo);
    gpu.ref->destroy_buffer(gpu.ref, vbo_front);
    gpu.ref->destroy_buffer(gpu.ref, vbo_back);
    gpu.ref->destroy_texture_view(gpu.ref, depth_view);
    gpu.ref->destroy_texture(gpu.ref, depth_tex);
    gpu.destroy(gpu.ref);
    win.ref->on_shutdown(win.ref, NULL);
    win.destroy(win.ref);

    printf("--- Done ---\n");
    return 0;
}
