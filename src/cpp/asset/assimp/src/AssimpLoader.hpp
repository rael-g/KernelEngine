#pragma once

#include <kernel_engine/asset/assimp/assimp_loader.h>
#include <kernel_engine/kernel/asset/asset_loader.h>

namespace kernel_engine::asset::assimp
{

class AssimpLoader
{
  public:
    explicit AssimpLoader(const ke_asset_loader_assimp_params *params);
    ~AssimpLoader();

    ke_asset_loader *ToApi();

    ke_result LoadModel(const char *path, ke_model_data **out);
    void FreeModel(ke_model_data *data);

  private:
    ke_allocator    *allocator_;
    ke_logger       *logger_;
    ke_asset_loader  api_{};
};

} // namespace kernel_engine::asset::assimp
