using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public partial struct ke_input_action_event
{
    [NativeTypeName("int32_t")]
    public int action_id;

    public ke_action_type type;

    public ke_action_phase phase;

    public float x;

    public float y;

    public float z;
}
