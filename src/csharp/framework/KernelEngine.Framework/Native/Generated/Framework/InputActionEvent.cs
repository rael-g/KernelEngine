using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public partial struct InputActionEvent
{
    [NativeTypeName("int32_t")]
    public int ActionId;

    [NativeTypeName("ke_action_type")]
    public NativeActionType Type;

    [NativeTypeName("ke_action_phase")]
    public ActionPhase Phase;

    public float X;

    public float Y;

    public float Z;
}
