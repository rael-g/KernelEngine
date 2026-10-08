#include <kernel_engine/common/error.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_commands.h>
#include <kernel_engine/render/gpu/gpu_enums.h>
#include <kernel_engine/render/gpu/gpu_render_target.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <kernel_engine/render/texture_target/gpu_render_target_texture_create.h>

#include "triangle_vs_wgsl.h"
#include "triangle_fs_wgsl.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { WIDTH = 256, HEIGHT = 256, BYTES_PER_TEXEL = 4 };

typedef struct readback
{
    bool done;
    bool ok;
} readback;

static void die(const char *msg, ke_error *err)
{
    if (err) { ke_error_fatal(err); }
    ke_error fallback = { .type = &KE_ERROR_GENERAL, .message = msg, .file = __FILE__, .line = __LINE__, .cause = NULL };
    ke_error_fatal(&fallback);
}

static void on_mapped(ke_gpu_buffer buffer, bool ok, void *user)
{
    (void)buffer;
    readback *r = user;
    r->ok = ok;
    r->done = true;
}

static void render_frame(ke_gpu_device *gpu, ke_gpu_render_target *target, ke_gpu_pipeline pipeline,
                         ke_gpu_texture texture, ke_gpu_buffer staging, uint32_t padded_row,
                         uint8_t *out_pixels)
{
    ke_error *err = NULL;
    ke_gpu_queue q = gpu->get_default_queue(gpu);

    ke_gpu_texture_view view = target->acquire(target, &err);
    if (view == KE_GPU_INVALID_HANDLE) die("acquire failed", err);

    ke_gpu_color_attachment ca = {
        .view        = view,
        .load_op     = KE_GPU_LOAD_OP_CLEAR,
        .store_op    = KE_GPU_STORE_OP_STORE,
        .clear_value = { .color = { 0.1f, 0.1f, 0.1f, 1.0f } },
    };
    ke_gpu_render_pass_params rpp = { .color_attachments = &ca, .color_attachment_count = 1 };

    ke_gpu_command_encoder *enc = gpu->create_command_encoder(gpu);
    ke_gpu_render_pass *rp = enc->begin_render_pass(enc, &rpp);
    rp->set_pipeline(rp, pipeline);
    rp->draw(rp, 3, 1, 0, 0);
    rp->end(rp);
    if (!enc->copy_texture_to_buffer(enc, texture, 0, 0, 0, staging, 0, padded_row, WIDTH, HEIGHT, &err))
        die("copy to buffer failed", err);
    ke_gpu_command_buffer *cmd = enc->finish(enc);
    enc->destroy(enc);
    ke_gpu_command_buffer *cmds[] = { cmd };
    gpu->queue_submit(gpu, q, cmds, 1);
    cmd->destroy(cmd);
    if (!target->present(target, &err)) die("present failed", err);

    readback r = { 0 };
    gpu->map_buffer_read(gpu, staging, 0, (size_t)padded_row * HEIGHT, on_mapped, &r);
    while (!r.done) gpu->queue_wait_idle(gpu, q);
    if (!r.ok) die("map for reading failed", NULL);

    const uint8_t *mapped = gpu->map_buffer(gpu, staging, 0, (size_t)padded_row * HEIGHT);
    if (!mapped) die("mapped range unavailable", NULL);
    for (uint32_t y = 0; y < HEIGHT; ++y)
        memcpy(out_pixels + (size_t)y * WIDTH * BYTES_PER_TEXEL, mapped + (size_t)y * padded_row, WIDTH * BYTES_PER_TEXEL);
    gpu->unmap_buffer(gpu, staging);
}

int main(void)
{
    printf("--- c_demo_15: offscreen capture ---\n");

    ke_error *err = NULL;
    ke_gpu_device_webgpu_params dp = { .logger = NULL, .enable_validation = 1 };
    ke_gpu_device_handle gpu = ke_gpu_device_webgpu_create(&dp, &err);
    if (!gpu.ref) die("gpu device create failed", err);

    ke_gpu_texture texture = gpu.ref->create_texture(gpu.ref, &(ke_gpu_texture_params){
        .width = WIDTH, .height = HEIGHT, .depth_or_array_layers = 1,
        .format = KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM, .dimension = KE_GPU_TEXTURE_DIM_2D,
        .usage = KE_GPU_TEXTURE_USAGE_COLOR_ATTACH | KE_GPU_TEXTURE_USAGE_COPY_SRC,
        .mip_level_count = 1, .sample_count = 1 });
    if (texture == KE_GPU_INVALID_HANDLE) die("texture create failed", NULL);

    ke_gpu_render_target_handle target = ke_gpu_render_target_texture_create(gpu.ref,
        &(ke_gpu_render_target_texture_params){ .texture = texture, .width = WIDTH, .height = HEIGHT,
                                                 .format = KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM }, &err);
    if (!target.ref) die("render target create failed", err);

    ke_gpu_capabilities caps = { 0 };
    gpu.ref->get_capabilities(gpu.ref, &caps);
    uint32_t align = caps.copy_bytes_per_row_alignment;
    uint32_t padded_row = (WIDTH * BYTES_PER_TEXEL + align - 1) / align * align;

    ke_gpu_buffer staging = gpu.ref->create_buffer(gpu.ref, &(ke_gpu_buffer_params){
        .size = (size_t)padded_row * HEIGHT,
        .usage = KE_GPU_BUFFER_USAGE_COPY_DST | KE_GPU_BUFFER_USAGE_MAP_READ }, &err);
    if (staging == KE_GPU_INVALID_HANDLE) die("staging buffer create failed", err);

    ke_gpu_shader_module vs = gpu.ref->create_shader_module(gpu.ref, &(ke_gpu_shader_module_params){
        .code = triangle_vs_wgsl, .byte_size = strlen(triangle_vs_wgsl), .entry_point = "vs_main" }, &err);
    if (vs == KE_GPU_INVALID_HANDLE) die("vertex shader creation failed", err);
    ke_gpu_shader_module fs = gpu.ref->create_shader_module(gpu.ref, &(ke_gpu_shader_module_params){
        .code = triangle_fs_wgsl, .byte_size = strlen(triangle_fs_wgsl), .entry_point = "fs_main" }, &err);
    if (fs == KE_GPU_INVALID_HANDLE) die("fragment shader creation failed", err);

    ke_gpu_render_pipeline_params pp = {
        .color_target_formats = { target.ref->format(target.ref) },
        .color_target_count = 1,
        .vertex_module = vs, .fragment_module = fs,
        .vertex_entry = "vs_main", .fragment_entry = "fs_main",
        .primitive_topology = KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .cull_mode = KE_GPU_CULL_MODE_NONE, .front_face = KE_GPU_FRONT_FACE_CCW,
        .blend_state = { .blend_enabled = 0, .src_color = KE_GPU_BLEND_FACTOR_ONE,
                         .dst_color = KE_GPU_BLEND_FACTOR_ZERO, .color_op = KE_GPU_BLEND_OP_ADD,
                         .src_alpha = KE_GPU_BLEND_FACTOR_ONE, .dst_alpha = KE_GPU_BLEND_FACTOR_ZERO,
                         .alpha_op = KE_GPU_BLEND_OP_ADD, .write_mask = 0x0F },
        .depth_stencil = { .depth_test_enabled = 0 },
    };
    ke_gpu_pipeline pipeline = gpu.ref->create_render_pipeline(gpu.ref, &pp);
    if (pipeline == KE_GPU_INVALID_HANDLE) die("pipeline creation failed", NULL);
    gpu.ref->destroy_shader_module(gpu.ref, vs);
    gpu.ref->destroy_shader_module(gpu.ref, fs);

    size_t image_bytes = (size_t)WIDTH * HEIGHT * BYTES_PER_TEXEL;
    uint8_t *first = malloc(image_bytes);
    uint8_t *second = malloc(image_bytes);
    if (!first || !second) die("out of memory", NULL);

    render_frame(gpu.ref, target.ref, pipeline, texture, staging, padded_row, first);
    render_frame(gpu.ref, target.ref, pipeline, texture, staging, padded_row, second);

    size_t differing = 0;
    size_t lit = 0;
    for (size_t i = 0; i < image_bytes; i += BYTES_PER_TEXEL)
    {
        if (memcmp(first + i, second + i, BYTES_PER_TEXEL) != 0) ++differing;
        if (memcmp(first + i, first, BYTES_PER_TEXEL) != 0) ++lit;
    }
    const uint8_t *center = first + ((size_t)(HEIGHT / 2) * WIDTH + WIDTH / 2) * BYTES_PER_TEXEL;
    printf("corner rgba %u %u %u %u, center rgba %u %u %u %u\n",
           first[0], first[1], first[2], first[3], center[0], center[1], center[2], center[3]);
    printf("%zu of %d texels differ from the corner (the triangle), %zu differ between the two frames\n",
           lit, WIDTH * HEIGHT, differing);

    free(first);
    free(second);
    gpu.ref->destroy_pipeline(gpu.ref, pipeline);
    gpu.ref->destroy_buffer(gpu.ref, staging);
    target.destroy(target.ref);
    gpu.ref->destroy_texture(gpu.ref, texture);
    gpu.destroy(gpu.ref);

    printf("--- Done ---\n");
    return differing == 0 && lit > 0 ? 0 : 1;
}
