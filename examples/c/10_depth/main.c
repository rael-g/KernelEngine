#include <kernel_engine/result/result.h>
#include <kernel_engine/window/window.h>
#include <kernel_engine/window/glfw/glfw_window.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_commands.h>
#include <kernel_engine/render/gpu/gpu_enums.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/webgpu/gpu_render_target_webgpu_window_create.h>

static const char depth_vs_wgsl[] = {
#embed "depth_vs.wgsl"
    , 0};
static const char depth_fs_wgsl[] = {
#embed "depth_fs.wgsl"
    , 0};
#include <string.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static void die_result(const char *what, ke_result result)
{
    fprintf(stderr, "%s failed with result code 0x%08x\n", what, (unsigned)result);
    exit(1);
}

static void check(const char *what, ke_result result)
{
    if (result != KE_OK) die_result(what, result);
}

typedef struct { float x, y, z, r, g, b; } vertex_t;

static const vertex_t back_verts[] = {
    { -0.6f, -0.6f, 0.5f,  1.0f, 0.2f, 0.2f },
    {  0.6f, -0.6f, 0.5f,  1.0f, 0.2f, 0.2f },
    {  0.6f,  0.6f, 0.5f,  1.0f, 0.2f, 0.2f },
    { -0.6f,  0.6f, 0.5f,  1.0f, 0.2f, 0.2f },
};

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
    ke_window_glfw_config wp = {
        .title = "c_demo_10 depth", .width = WIDTH, .height = HEIGHT,
    };
    ke_window_handle win = { 0 };
    ke_result made_window = ke_window_glfw_create(NULL, &wp, &win);
    if (made_window != KE_OK) die_result("window", made_window);
    ke_result window_ready = win.ref->on_initialize(win.ref);
    if (window_ready != KE_OK) die_result("window init", window_ready);

    ke_gpu_device_webgpu_params dp = { .enable_validation = 1 };
    ke_gpu_device_handle gpu = { 0 };
    check("gpu device", ke_gpu_device_webgpu_create(&dp, &gpu));

    ke_gpu_render_target_handle target = { 0 };
    check("render target create", ke_gpu_render_target_webgpu_window_create(&(ke_gpu_render_target_webgpu_window_params){ .device = gpu.ref, .window = win.ref }, &target));

    ke_gpu_texture depth_tex = { 0 };
    check("depth texture", gpu.ref->create_texture(gpu.ref, &(ke_gpu_texture_params){
        .width = WIDTH, .height = HEIGHT, .depth_or_array_layers = 1,
        .format = KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .dimension = KE_GPU_TEXTURE_DIM_2D,
        .usage = KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH,
        .mip_level_count = 1, .sample_count = 1,
    }, &depth_tex));

    ke_gpu_texture_view depth_view = { 0 };
    check("depth view", gpu.ref->create_texture_view(gpu.ref, depth_tex,
        &(ke_gpu_texture_view_params){
            .format = KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
            .dimension = KE_GPU_TEXTURE_DIM_2D,
            .aspect = KE_GPU_TEXTURE_ASPECT_DEPTH,
            .mip_level_count = 1, .array_layer_count = 1,
        }, &depth_view));

    ke_gpu_buffer vbo_back = { 0 };
    check("back vertex buffer creation", gpu.ref->create_buffer(gpu.ref, &(ke_gpu_buffer_params){
        .initial_data = back_verts,  .size = sizeof(back_verts),  .usage = KE_GPU_BUFFER_USAGE_VERTEX }, &vbo_back));
    ke_gpu_buffer vbo_front = { 0 };
    check("front vertex buffer creation", gpu.ref->create_buffer(gpu.ref, &(ke_gpu_buffer_params){
        .initial_data = front_verts, .size = sizeof(front_verts), .usage = KE_GPU_BUFFER_USAGE_VERTEX }, &vbo_front));
    ke_gpu_buffer ibo = { 0 };
    check("index buffer creation", gpu.ref->create_buffer(gpu.ref, &(ke_gpu_buffer_params){
        .initial_data = quad_idx, .size = sizeof(quad_idx), .usage = KE_GPU_BUFFER_USAGE_INDEX }, &ibo));

    ke_gpu_shader_module vs = { 0 };
    check("create_shader_module", gpu.ref->create_shader_module(gpu.ref, &(ke_gpu_shader_module_params){
        .code = depth_vs_wgsl, .byte_size = strlen(depth_vs_wgsl), .label = "vs_main" }, &vs));
    ke_gpu_shader_module fs = { 0 };
    check("create_shader_module", gpu.ref->create_shader_module(gpu.ref, &(ke_gpu_shader_module_params){
        .code = depth_fs_wgsl, .byte_size = strlen(depth_fs_wgsl), .label = "fs_main" }, &fs));

    ke_gpu_vertex_attribute attrs[] = {
        { .shader_location = 0, .format = KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 },
        { .shader_location = 1, .format = KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = sizeof(float) * 3 },
    };
    ke_gpu_vertex_buffer_layout vbl = {
        .stride = sizeof(vertex_t), .step_mode = KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 2, .attributes = attrs,
    };
    ke_gpu_render_pipeline_params pp = {
        .color_target_formats = { target.ref->format(target.ref) },
        .color_target_count = 1,
        .vertex_module = vs, .fragment_module = fs,
        .vertex_entry = "vs_main", .fragment_entry = "fs_main",
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
    ke_gpu_pipeline pipeline = { 0 };
    check("pipeline", gpu.ref->create_render_pipeline(gpu.ref, &pp, &pipeline));

    gpu.ref->destroy_shader_module(gpu.ref, vs);
    gpu.ref->destroy_shader_module(gpu.ref, fs);

    ke_gpu_queue q = gpu.ref->get_default_queue(gpu.ref);

    printf("Rendering two overlapping quads with depth test. Close to exit.\n");
    printf("Blue quad (z=0.2) should appear in front of red quad (z=0.5).\n");

    while (!win.ref->should_close(win.ref))
    {
        win.ref->poll_events(win.ref);

        ke_gpu_texture_view color_view = { 0 };
        check("acquire", target.ref->acquire(target.ref, &color_view));
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

        ke_gpu_command_encoder_handle enc_handle = { 0 };
        check("create_command_encoder", gpu.ref->create_command_encoder(gpu.ref, NULL, &enc_handle));

        ke_gpu_command_encoder *enc = enc_handle.ref;
        ke_gpu_render_pass *rp = enc->begin_render_pass(enc, &rpp);
        rp->set_pipeline(rp, pipeline);
        rp->set_index_buffer(rp, ibo, KE_GPU_INDEX_FORMAT_UINT16, 0);

        rp->set_vertex_buffer(rp, 0, vbo_back, 0);
        rp->draw_indexed(rp, 6, 1, 0, 0, 0);

        rp->set_vertex_buffer(rp, 0, vbo_front, 0);
        rp->draw_indexed(rp, 6, 1, 0, 0, 0);

        rp->end(rp);

        ke_gpu_command_buffer_handle cmd = { 0 };
        check("finish", enc->finish(enc, &cmd));
        enc_handle.destroy(enc);
        ke_gpu_command_buffer *cmds[] = { cmd.ref };
        gpu.ref->queue_submit(gpu.ref, q, cmds, 1);
        cmd.destroy(cmd.ref);
        check("present", target.ref->present(target.ref));
        gpu.ref->queue_poll(gpu.ref, q);
    }

    gpu.ref->destroy_pipeline(gpu.ref, pipeline);
    gpu.ref->destroy_buffer(gpu.ref, ibo);
    gpu.ref->destroy_buffer(gpu.ref, vbo_front);
    gpu.ref->destroy_buffer(gpu.ref, vbo_back);
    gpu.ref->destroy_texture_view(gpu.ref, depth_view);
    gpu.ref->destroy_texture(gpu.ref, depth_tex);
    target.destroy(target.ref);
    gpu.destroy(gpu.ref);
    win.ref->on_shutdown(win.ref);
    win.destroy(win.ref);

    printf("--- Done ---\n");
    return 0;
}
