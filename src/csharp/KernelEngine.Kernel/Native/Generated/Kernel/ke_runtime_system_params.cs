namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_runtime_system_params
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public ke_phase phase;

    public void* user_data;

    [NativeTypeName("void (*)(ke_runtime *, void *, float)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void*, float, void> execute;
}
