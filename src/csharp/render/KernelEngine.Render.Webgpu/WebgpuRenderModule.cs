using KernelEngine.Common.Native;
using KernelEngine.Ecs;
using KernelEngine.Render.Webgpu.Native;
using KernelEngine.Runtime;
using KernelEngine.Window;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Render.Webgpu;

/// <summary>
/// Render v2 (webgpu) as an <see cref="IRuntimeModule"/>. Creates the GPU device
/// from the window and installs the render path (ke_render_module) which
/// registers begin/clear/end as KE_PHASE_RENDER systems on the runtime. The host
/// just ticks the runtime — no render calls in the loop. Coexists with
/// BgfxRenderModule as an alternate DI choice.
/// </summary>
public sealed unsafe class WebgpuRenderModule : IRuntimeModule
{
    private ke_gpu_device_handle _device;
    private ke_render_module_handle _module;

    public string Name => "Webgpu.Render";

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var window = services.GetRequiredService<IWindow>();
        var ecs    = services.GetRequiredService<IEcs>();

        var win = ((INativeWindow)window).Native;
        var rt  = ((INativeRuntime)runtime).Native;
        var ec  = ((INativeEcs)ecs).Native;

        ke_error* err = null;

        var dp = new ke_gpu_device_webgpu_params { window = win, enable_validation = 1 };
        _device = KernelEngine.Render.Webgpu.Native.NativeMethods.gpu_device_webgpu_create(&dp, &err);
        if (_device.@ref == null)
            throw new InvalidOperationException("webgpu device create failed");

        _module = KernelEngine.Render.Webgpu.Native.NativeMethods.render_module_create(rt, ec, _device.@ref, 1, &err);
        if (_module.@ref == null)
            throw new InvalidOperationException("render module create failed");
    }

    public void OnUnload(IRuntime runtime, IServiceProvider services)
    {
        if (_module.@ref != null && _module.destroy != null)
            _module.destroy(_module.@ref);
        if (_device.@ref != null && _device.destroy != null)
            _device.destroy(_device.@ref);
    }
}
