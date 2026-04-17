namespace KernelEngine.Kernel.Native;

public partial struct ke_msg_key_event
{
    [NativeTypeName("int32_t")]
    public int key;

    [NativeTypeName("int32_t")]
    public int action;
}
