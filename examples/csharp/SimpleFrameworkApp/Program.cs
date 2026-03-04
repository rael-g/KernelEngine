using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

using KernelEngine.Framework;
using KernelEngine.Core;
using KernelEngine.Glfw;
using KernelEngine.Bgfx;
using KernelEngine.Logging.Serilog;

using Serilog;

namespace SimpleFrameworkApp;

class Program
{
    static void Main(string[] args)
    {
        var builder = Host.CreateApplicationBuilder(args);

        builder.Services.AddKernelEngineCore();
        builder.Services.AddSerilog(new LoggerConfiguration()
            .MinimumLevel.Verbose()
            .WriteTo.Console());

        builder.Services.AddWindowGlfw(1280, 720, "KernelEngine Pure Static Host");
        builder.Services.AddRenderBgfx("src/cpp/render/bgfx/shaders");

        using var app = builder.Build()
            .AsKernelEngine();

        float hue = 0.0f;
        var renderer = app.Services.GetRequiredService<IRenderer>();

        app.OnUpdate += () => 
        {
            hue += 0.005f;
            if (hue > 1.0f) hue -= 1.0f;
            renderer.ClearColor(hue, 0.2f, 0.4f, 1.0f);
        };

        app.Run();
    }
}
