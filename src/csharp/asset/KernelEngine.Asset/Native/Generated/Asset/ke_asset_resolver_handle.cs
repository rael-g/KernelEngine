using KernelEngine.Common.Native;

namespace KernelEngine.Asset.Native;

public unsafe partial struct ke_asset_resolver_handle
{
    public ke_asset_resolver* @ref;

    [NativeTypeName("void (*)(ke_asset_resolver *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, void> destroy;
}
