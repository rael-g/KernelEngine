using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

[NativeTypeName("unsigned int")]
public enum ke_action_phase : uint
{
    KE_ACTION_PHASE_STARTED = 1,
    KE_ACTION_PHASE_PERFORMED = 2,
    KE_ACTION_PHASE_CANCELED = 3,
}
