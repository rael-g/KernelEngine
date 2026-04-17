namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_log_event
{
    [NativeTypeName("int32_t")]
    public int level;

    [NativeTypeName("const char *")]
    public sbyte* tag;

    [NativeTypeName("const char *")]
    public sbyte* message;
}
