#pragma once

#include <kernel_engine/asset/assimp/assimp_loader.h>
#include <kernel_engine/asset/asset_loader.h>

namespace kernel_engine::asset::assimp
{

class AssimpLoader
{
  public:
    explicit AssimpLoader(const ke_asset_loader_assimp_params *params);
    ~AssimpLoader();

    ke_asset_loader *ToApi();

    /// Owner-handle destroy: tears down the loader and frees its allocation.
    static void DestroyApi(ke_asset_loader *self);

    ke_result LoadModel(const char *path, ke_model_data **out, ke_error **out_error = nullptr);
    void FreeModel(ke_model_data *data);
    ke_task *LoadModelAsync(ke_task_scheduler *scheduler,
                            const char *path,
                            ke_load_model_complete_func on_complete,
                            void *user_data);

  private:
    ke_allocator    *allocator_;
    ke_logger       *logger_;
    ke_asset_loader  api_{};
};

} // namespace kernel_engine::asset::assimp
