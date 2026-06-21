#include <kernel_engine/common/error.h>
#include <kernel_engine/render/gpu_device.h>
#include <kernel_engine/render/webgpu/gpu_device_webgpu_create.h>
#include <stdio.h>

int main(void)
{
    printf("--- KernelEngine GPU Device Demo ---\n");

    ke_error *err = NULL;
    ke_gpu_device_webgpu_params params = {
        .logger            = NULL,
        .enable_validation = 1,
    };

    ke_gpu_device_handle gpu = ke_gpu_device_webgpu_create(&params, &err);
    if (!gpu.ref)
    {
        if (err)
            printf("ERROR [%s]: %s\n", err->type->name, err->message);
        else
            printf("ERROR: ke_gpu_device_webgpu_create returned null\n");
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
