#include <kernel_engine/result/result.h>
#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <stdio.h>

int main(void)
{
    printf("--- KernelEngine GPU Device Demo ---\n");

    ke_gpu_device_webgpu_config params = {
        .enable_validation = 1,
    };

    ke_gpu_device_handle gpu = { 0 };
    ke_result made = ke_gpu_device_webgpu_create(NULL, &params, &gpu);
    if (made != KE_OK)
    {
        printf("ERROR: ke_gpu_device_webgpu_create failed with result code 0x%08x\n", (unsigned)made);
        return 1;
    }

    printf("GPU device created\n");

    ke_gpu_capabilities caps = {0};
    gpu.ref->get_capabilities(gpu.ref, &caps);
    printf("max_texture_dimension_2d : %u\n", caps.max_texture_dimension_2d);
    printf("max_bind_groups          : %u\n", caps.max_bind_groups);

    gpu.destroy(gpu.ref);
    printf("GPU device destroyed\n");

    printf("--- Demo Complete ---\n");
    return 0;
}
