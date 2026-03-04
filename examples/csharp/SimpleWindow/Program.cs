using System;
using KernelEngine.Core;
using KernelEngine.Core.Allocators;
using KernelEngine.Core.Logging;
using KernelEngine.Core.Messaging;
using KernelEngine.Glfw;
using KernelEngine.Bgfx;

namespace SimpleWindow;

class Program
{
    static void Main(string[] args)
    {
        Console.WriteLine("--- KernelEngine Static NativeAOT Demo ---");

        // 1. Setup Infrastructure
        using var allocator = NativeAllocator.CreateMalloc();
        using var logger = NativeLogger.Create(allocator);
        using var messagePipe = NativeMessagePipe.Create(allocator, logger);

        // 2. Setup Engine
        using var engine = Engine.Create(allocator, logger, messagePipe);

        // 3. Setup Window System
        using var windowSystem = new GlfwWindowSystem(allocator, 800, 600, "C# Static AOT Window", logger, messagePipe);
        engine.RegisterSystem(windowSystem);

        // 4. Setup Render System
        using var renderSystem = new BgfxRenderSystem(allocator, windowSystem, "src/cpp/render/bgfx/shaders", logger, messagePipe);
        engine.RegisterSystem(renderSystem);

        // 5. Run
        engine.Initialize();

        float hue = 0.0f;
        while (!windowSystem.ShouldClose())
        {
            hue += 0.005f;
            if (hue > 1.0f) hue -= 1.0f;

            renderSystem.ClearColor(hue, 0.2f, 0.4f, 1.0f);
            engine.Tick();
        }

        engine.Shutdown();
        Console.WriteLine("--- Demo Complete ---");
    }
}
