#include <string>

static int g_ctor_ran = 0;
static std::string g_marker;

namespace
{
struct Init
{
    Init()
    {
        g_ctor_ran = 1;
        g_marker = "constructed";
    }
};
Init g_init;
}

extern "C" int ke_probe_ctor_ran(void)
{
    return g_ctor_ran;
}

extern "C" const char *ke_probe_marker(void)
{
    return g_marker.c_str();
}
