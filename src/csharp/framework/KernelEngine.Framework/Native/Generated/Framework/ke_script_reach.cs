using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

[NativeTypeName("unsigned int")]
public enum ke_script_reach : uint
{
    KE_SCRIPT_REACH_SELF = 0,
    KE_SCRIPT_REACH_ANY = 1,
}
