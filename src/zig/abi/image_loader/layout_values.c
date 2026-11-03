#include <stddef.h>
#include <kernel_engine/asset/image_loader.h>
const unsigned long long layout_values[] = {
    sizeof(ke_image_loader),
    offsetof(ke_image_loader, handle),
    offsetof(ke_image_loader, load_image),
    offsetof(ke_image_loader, free_image),
    sizeof(ke_image_loader_handle),
    offsetof(ke_image_loader_handle, ref),
    offsetof(ke_image_loader_handle, destroy),
    0,
};
