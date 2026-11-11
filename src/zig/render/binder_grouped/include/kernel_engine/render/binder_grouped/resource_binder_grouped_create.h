#ifndef KERNEL_ENGINE_RENDER_BINDER_GROUPED_RESOURCE_BINDER_GROUPED_CREATE_H_
#define KERNEL_ENGINE_RENDER_BINDER_GROUPED_RESOURCE_BINDER_GROUPED_CREATE_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/common/export.h>
#include <kernel_engine/io/io.h>
#include <kernel_engine/render/binding/resource_binder.h>
#include <kernel_engine/render/gpu/gpu_device.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_RENDER_BINDER_GROUPED_API
#  ifdef KE_RENDER_BINDER_GROUPED_EXPORT
#    define KE_RENDER_BINDER_GROUPED_API KE_EXPORT
#  else
#    define KE_RENDER_BINDER_GROUPED_API KE_IMPORT
#  endif
#endif

/// [bag] The values a grouped resource binder is created with, each applied as given.
typedef struct ke_render_resource_binder_grouped_config
{
    /// [utf8] Directory the build wrote each compiled shader's reflection into; copied.
    const char *shader_dir;
} ke_render_resource_binder_grouped_config;

/**
 * Creates a resource binder that gives every group of a shader one bind group and every material
 * one bind group of its own.
 * @param device Borrowed; must outlive the binder.
 * @param io     [provider] Borrowed; must outlive the binder. The reflection is read through it.
 * @param config [borrowed] Required; every field is read as given.
 * @return KE_OK, or KE_RESULT_INVALID_ARGUMENT when @p device, @p io, @p config or its shader
 *         directory is NULL.
 * @param out_binder [out] Receives the handle; left zeroed on failure.
 */
KE_RENDER_BINDER_GROUPED_API ke_result ke_render_resource_binder_grouped_create(
    ke_gpu_device *device, ke_io *io, const ke_render_resource_binder_grouped_config *config,
    ke_render_resource_binder_handle *out_binder);

#ifdef __cplusplus
}
#endif

#endif
