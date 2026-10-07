namespace Kabic.Tests;

internal static class ProbeConvention
{
    public static readonly Convention Value = new ConventionBuilder()
        .Symbols("ke_", "_handle", "_create", "_component", "_params")
        .Booleans("ke_bool")
        .Bindings("kernel_engine", "KernelEngine.Common.Native")
        .Managed("KernelEngine.Common")
        .Failure("ke_error", "ke_error_type", "ke_error_is", "KE_ERROR_GENERAL",
            "", [], "NativeErrors", "KernelEngine", "")
        .AddError("KE_ERROR_GENERAL", "ke.error", "InvalidOperationException", "General")
        .AddError("KE_ERROR_NOT_FOUND", "ke.error.not_found", "KeyNotFoundException")
        .AddError("KE_ERROR_IO", "ke.error.io", "IOException")
        .AddError("KE_ERROR_OUT_OF_MEMORY", "ke.error.out_of_memory", "OutOfMemoryException")
        .AddError("KE_ERROR_INVALID_ARGUMENT", "ke.error.invalid_argument", "ArgumentException")
        .AddError("KE_ERROR_NOT_INITIALIZED", "ke.error.not_initialized", "InvalidOperationException")
        .AddError("KE_ERROR_NOT_SUPPORTED", "ke.error.not_supported", "NotSupportedException")
        .AddError("KE_ERROR_ALREADY_EXISTS", "ke.error.already_exists", "InvalidOperationException")
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
