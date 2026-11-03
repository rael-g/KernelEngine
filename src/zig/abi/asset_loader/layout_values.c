#include <stddef.h>
#include <kernel_engine/asset/asset_loader.h>
const unsigned long long layout_values[] = {
    sizeof(ke_asset_loader),
    offsetof(ke_asset_loader, handle),
    offsetof(ke_asset_loader, load_model),
    offsetof(ke_asset_loader, free_model),
    offsetof(ke_asset_loader, load_model_async),
    sizeof(ke_asset_loader_handle),
    offsetof(ke_asset_loader_handle, ref),
    offsetof(ke_asset_loader_handle, destroy),
    0,
};
