#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_FILES_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_FILES_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/commands.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// Scene files: a text that spawns nodes of registered types and writes their components, as
    /// a program calling the node types and the ecs would.
    typedef struct ke_scene_files
    {
        void *handle;

        /// Records into @p commands every node the scene file at @p path declares, each one
        /// without a parent of its own under @p parent, each spawned as a node of its type with the values its blocks write.
        /// The nodes exist once @p commands is applied.
        /// @param path     [utf8] A `res://` path is resolved by the asset resolver; any other is
        ///                 read as written.
        /// @param parent   KE_ENTITY_INVALID places them at the root.
        /// @param out_root [out,optional] Receives the first node; KE_ENTITY_INVALID for a file
        ///                 that declares none.
        /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p path or @p commands, or a fault
        ///         in what the file says; KE_RESULT_NOT_FOUND for a missing file or a type never
        ///         registered; KE_RESULT_IO for a file that does not parse, or the queue's code.
        ///         On a failure @p commands may hold part of the scene.
        ke_result (*instantiate)(struct ke_scene_files *self, const char *path, ke_entity parent, ke_ecs_commands *commands, ke_entity *out_root);
    } ke_scene_files;

    /// [owner]
    typedef struct ke_scene_files_handle
    {
        ke_scene_files *ref;
        void (*destroy)(ke_scene_files *self);
    } ke_scene_files_handle;

#ifdef __cplusplus
}
#endif

#endif
