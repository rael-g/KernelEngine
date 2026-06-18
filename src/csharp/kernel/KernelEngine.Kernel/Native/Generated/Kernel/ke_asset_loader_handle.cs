namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_asset_loader_handle
{
    public ke_asset_loader* @ref;

    [NativeTypeName("void (*)(ke_asset_loader *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_loader*, void> destroy;
}
