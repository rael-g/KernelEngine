#include <kernel_engine/core/common/hash.h>

uint64_t ke_hash_string(const char *str)
{
    uint64_t hash = 0xcbf29ce484222325ULL;
    if (!str)
    {
        return 0;
    }
    while (*str)
    {
        hash ^= (uint64_t)(unsigned char)*str++;
        hash *= 0x100000001b3ULL;
    }
    return hash;
}
