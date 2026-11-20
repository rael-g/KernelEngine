#include "pong.h"

#include <kernel_engine/sdk/defaults.h>

#include <stdio.h>

static pong_game game;

static void pong_release(void *ref)
{
    (void)ref;
}

static ke_result pong_create(const ke_part *self, const ke_part_bound *slots, ke_settings *settings, ke_owner *out)
{
    (void)self;
    (void)settings;
    game.types = slots[0].instances[0];
    ke_result made = pong_register(&game);
    if (made == KE_OK) *out = (ke_owner){ .ref = &game, .destroy = pong_release };
    return made;
}

static const ke_part_slot pong_slots[] = { { .name = "node_types", .contract = "ke_node_types", .cardinality = KE_PART_CARDINALITY_ONE } };

static const ke_part pong_part = { .name = "pong_nodes", .slots = pong_slots, .slot_count = 1, .create = pong_create };

int main(void)
{
    ke_sdk_host host;
    ke_result made = ke_sdk_host_open("pong", &host);
    ke_assembly *a = host.assembly.ref;
    if (made == KE_OK) made = ke_sdk_defaults_compose(a);
    if (made == KE_OK) made = a->add_part(a, &pong_part);
    if (made == KE_OK) made = a->add_instance(a, "pong_nodes", "pong_nodes", NULL);
    if (made == KE_OK) made = ke_sdk_host_run(&host);
    ke_sdk_host_close(&host);
    if (made != KE_OK)
    {
        fprintf(stderr, "pong failed with result code 0x%08x\n", (unsigned)made);
        return 1;
    }
    return 0;
}
