// Probe payload for the Windows DLL CRT-init tests: a global whose constructor
// is non-trivial, so it only ever runs if the CRT's C++ initializer section is
// executed at DLL attach. Reading `ke_probe_ctor_ran` back as 0 from a loaded
// DLL means the initializers were skipped.
//
// The std::string is deliberate: a POD assignment could be folded into static
// data by the compiler, which would make the probe pass without any
// initializer actually running.
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
} // namespace

extern "C" int ke_probe_ctor_ran(void)
{
    return g_ctor_ran;
}

extern "C" const char *ke_probe_marker(void)
{
    return g_marker.c_str();
}
