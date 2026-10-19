#ifndef KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_SOURCE_H_
#define KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_SOURCE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/configuration/configuration.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// Reads values from somewhere outside the process into a configuration, through its setter
    /// slots. A source keeps nothing between loads; which store it writes to is the caller's choice.
    typedef struct ke_configuration_source
    {
        void *handle;

        /// Writes what @p path holds into @p cfg. A path that does not exist writes nothing and
        /// succeeds. Writes made before a failure stay.
        /// @param cfg  [borrowed] The store written to.
        /// @param path [utf8] Where the values are read from.
        /// @return false, with the error set, when the content cannot be read or a write fails.
        bool (*load)(struct ke_configuration_source *self, ke_configuration *cfg,
                     const char *path, ke_error **out_error);
    } ke_configuration_source;

    typedef struct ke_configuration_source_handle
    {
        ke_configuration_source *ref;
        void (*destroy)(ke_configuration_source *self);
    } ke_configuration_source_handle;

#ifdef __cplusplus
}
#endif

#endif
