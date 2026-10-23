using Kabic.Numerics;

namespace Kabic.Tests;

internal static class ProbeConvention
{
    public static readonly Convention Value = new ConventionBuilder()
        .UseNumerics()
        .Symbols("ke_", "_handle", "_create", "_component", "_params")
        .Bindings("kernel_engine", "KernelEngine.Common.Native")
        .Managed("KernelEngine.Common")
        .Result("ke_result", "KE_OK", "KernelEngine.Result.Native.ke_result", "KernelEngine.NativeResults")
        .AddResultCode("KE_RESULT_GENERAL", "InvalidOperationException")
        .AddResultCode("KE_RESULT_NOT_FOUND", "KeyNotFoundException")
        .AddResultCode("KE_RESULT_IO", "IOException")
        .AddResultCode("KE_RESULT_OUT_OF_MEMORY", "OutOfMemoryException")
        .AddResultCode("KE_RESULT_INVALID_ARGUMENT", "ArgumentException")
        .AddResultCode("KE_RESULT_NOT_INITIALIZED", "InvalidOperationException")
        .AddResultCode("KE_RESULT_NOT_SUPPORTED", "NotSupportedException")
        .AddResultCode("KE_RESULT_ALREADY_EXISTS", "InvalidOperationException")
        .AddHandleType("ke_mesh_handle", "KernelEngine.Render.MeshHandle")
        .AddHandleType("ke_material_handle", "KernelEngine.Render.MaterialHandle")
        .AddHandleType("ke_texture_handle", "KernelEngine.Render.TextureHandle")
        .AddHandleType("ke_ui_font_handle", "KernelEngine.Render.FontHandle")
        .AddTypeName("ke_ecs", "EcsRegistry")
        .AddTypeName("ke_asset_resolver", "NativeAssetResolver")
        .AddTypeName("ke_input_actions", "NativeInputActions")
        .AddTypeName("ke_physics_2d", "Physics2D")
        .AddTypeName("ke_body_type_2d", "BodyType2D")
        .AddTypeName("ke_phase", "RuntimePhase")
        .AddTypeName("ke_access", "RuntimeAccess")
        .Build();
}
