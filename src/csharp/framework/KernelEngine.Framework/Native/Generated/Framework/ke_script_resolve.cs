using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

[NativeTypeName("unsigned int")]
public enum ke_script_resolve : uint
{
    KE_SCRIPT_RESOLVE_FOUND = 0,
    KE_SCRIPT_RESOLVE_NONE = 1,
    KE_SCRIPT_RESOLVE_AMBIGUOUS = 2,
}
