namespace KernelEngine.Kernel.Native;

public partial struct ke_component_access
{
    [NativeTypeName("ke_component_id")]
    public uint cid;

    public ke_access access;
}
