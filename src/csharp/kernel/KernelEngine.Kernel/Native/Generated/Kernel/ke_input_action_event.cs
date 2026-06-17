namespace KernelEngine.Kernel.Native;

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
