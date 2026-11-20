#include <stddef.h>
#include <kernel_engine/tasks/completion.h>
const unsigned long long layout_values[] = {
    sizeof(ke_completion),
    offsetof(ke_completion, handle),
    offsetof(ke_completion, poll),
    offsetof(ke_completion, wait),
    offsetof(ke_completion, release),
    0,
};
