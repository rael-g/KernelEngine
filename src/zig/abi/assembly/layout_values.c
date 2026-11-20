#include <stddef.h>
#include <kernel_engine/assembly/assembly.h>
#include <kernel_engine/assembly/composition_source.h>
const unsigned long long layout_values[] = {
    sizeof(ke_assembly),
    offsetof(ke_assembly, handle),
    offsetof(ke_assembly, route_log),
    offsetof(ke_assembly, add_part),
    offsetof(ke_assembly, add_instance),
    offsetof(ke_assembly, add_external),
    offsetof(ke_assembly, bind),
    offsetof(ke_assembly, order),
    offsetof(ke_assembly, set_default),
    offsetof(ke_assembly, resolve),
    offsetof(ke_assembly, advance),
    offsetof(ke_assembly, get),
    sizeof(ke_assembly_handle),
    offsetof(ke_assembly_handle, ref),
    offsetof(ke_assembly_handle, destroy),
    sizeof(ke_composition_source),
    offsetof(ke_composition_source, handle),
    offsetof(ke_composition_source, load),
    sizeof(ke_composition_source_handle),
    offsetof(ke_composition_source_handle, ref),
    offsetof(ke_composition_source_handle, destroy),
    0,
};
