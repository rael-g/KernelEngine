#include <stddef.h>
#include <kernel_engine/ecs/variant.h>
const unsigned long long layout_values[] = {
    sizeof(ke_variant),
    offsetof(ke_variant, type),
    sizeof(ke_variant_table_entry),
    offsetof(ke_variant_table_entry, key),
    offsetof(ke_variant_table_entry, value),
    offsetof(ke_variant_table_entry, consumed),
    sizeof(ke_variant_table),
    offsetof(ke_variant_table, count),
    offsetof(ke_variant_table, entries),
    0,
};
