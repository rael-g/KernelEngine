#ifndef KERNEL_ENGINE_RENDER_BINDER_GROUPED_RESOURCE_BINDER_GROUPED_CREATE_H_
#define KERNEL_ENGINE_RENDER_BINDER_GROUPED_RESOURCE_BINDER_GROUPED_CREATE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/common/export.h>
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

/// What a grouped resource binder is built on.
typedef struct ke_render_resource_binder_grouped_params
{
    /// Borrowed; must outlive the binder.
    ke_gpu_device *device;
    /// [utf8] Directory the build wrote each compiled shader's reflection into; copied.
    const char    *shader_dir;
} ke_render_resource_binder_grouped_params;

/**
 * Creates a resource binder that gives every group of a shader one bind group and every material
 * one bind group of its own.
 * @return Handle whose @c ref is NULL on failure, with the error filled: invalid argument when
 *         @p params, its device or its shader directory is NULL.
 */
KE_RENDER_BINDER_GROUPED_API ke_render_resource_binder_handle ke_render_resource_binder_grouped_create(
    const ke_render_resource_binder_grouped_params *params, ke_error **out_error);

#ifdef __cplusplus
}
#endif

#endif
