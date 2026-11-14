using KernelEngine.Async.Enki;
using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Io.Pool;
using KernelEngine.Job.Enki;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render;
using KernelEngine.Render.Webgpu;
using KernelEngine.Render.Webgpu.Native;
using KernelEngine.Runtime;
using KernelEngine.Schedule;
using KernelEngine.Scheduler;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Text.StbTrueType;
using KernelEngine.View;
using KernelEngine.Window.Glfw;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;

namespace KernelEngine;

/// <summary>Registration of the common implementation of every part of an engine.</summary>
public static class DefaultCore
{
    /// <summary>
    /// Registers, under its contract, the common implementation of every part the host has not registered yet, each
    /// configured once by the project file in <paramref name="projectDir"/>; and the default modules and renderer.
    /// </summary>
    /// <param name="services">The collection the parts are registered in.</param>
    /// <param name="projectDir">The directory holding the project file, its scenes and its assets.</param>
    public static IServiceCollection AddDefaultCore(this IServiceCollection services, string projectDir)
    {
        var root = projectDir.TrimEnd(Path.DirectorySeparatorChar);
        static ILoggerFactory? Log(IServiceProvider sp) => sp.GetService<ILoggerFactory>();
        static T Get<T>(IServiceProvider sp) where T : notnull => sp.GetRequiredService<T>();

        services.TryAddSingleton<TaskPool.TaskPool>(sp => new EnkiTaskPool(Log(sp), new() { WorkerCount = uint.MaxValue }));
        services.TryAddSingleton<Job.JobSystem>(sp => new EnkiJobSystem(Log(sp), new() { WorkerCount = uint.MaxValue }));
        services.TryAddSingleton<FileSystem.FileSystem>(sp => new StdFileSystem(Log(sp), new() { Root = "." }));
        services.TryAddSingleton<Io.Io>(sp => new PoolIo(Log(sp), Get<TaskPool.TaskPool>(sp), Get<FileSystem.FileSystem>(sp)));
        services.TryAddSingleton<ConfigurationSource>(sp => new ConfigurationTomlConfigurationSource(Log(sp), Get<Io.Io>(sp)));
        services.TryAddSingleton<Configuration.Configuration>(sp =>
        {
            var config = new DefaultConfiguration(Log(sp));
            Get<ConfigurationSource>(sp).Load(config, Path.Combine(root, "Project"));
            return config;
        });
        services.TryAddSingleton<Async.Async>(sp =>
        {
            var config = Get<Configuration.Configuration>(sp);
            return new EnkiAsync(Log(sp), new()
            {
                WorkerCount = (uint)config.GetInt("async", "worker_count", 2),
                SubmitCapacity = (uint)config.GetInt("async", "submit_capacity", 1024),
            });
        });
        services.TryAddSingleton<Input.Input>(_ => new Input.DefaultInput());
        services.TryAddSingleton<Window.Window>(sp =>
        {
            var config = Get<Configuration.Configuration>(sp);
            return new GlfwWindow(Log(sp), Get<Input.Input>(sp), new()
            {
                Title = config.GetString("runtime.window", "title", "KernelEngine"),
                Width = (int)config.GetInt("runtime.window", "width", 1280),
                Height = (int)config.GetInt("runtime.window", "height", 720),
                Fullscreen = config.GetBool("runtime.window", "fullscreen", false),
            });
        });
        services.TryAddSingleton<Ecs.EcsRegistry>(sp => new FlecsEcsRegistry(Log(sp), new() { ReservedIdCapacity = 1048576 }));
        services.TryAddKeyedSingleton<Ecs.EcsRegistry>("render", (sp, _) => new FlecsEcsRegistry(Log(sp), new() { ReservedIdCapacity = 1048576 }));
        services.TryAddKeyedSingleton<Schedule.Schedule>("render", (sp, _) => new DefaultSchedule(Log(sp), sp.GetRequiredKeyedService<Ecs.EcsRegistry>("render"), Get<Job.JobSystem>(sp), new() { RefuseAmbiguity = false }));
        services.TryAddSingleton<Extraction.Extraction>(sp => new Extraction.DefaultExtraction(Log(sp), Get<Ecs.EcsRegistry>(sp), sp.GetRequiredKeyedService<Ecs.EcsRegistry>("render"), Get<Scheduler.Scheduler>(sp), sp.GetRequiredKeyedService<Schedule.Schedule>("render")));
        services.TryAddSingleton<Func<Schedule.Schedule>>(sp => () => new DefaultSchedule(Log(sp), Get<Ecs.EcsRegistry>(sp), Get<Job.JobSystem>(sp), new() { RefuseAmbiguity = false }));
        services.TryAddSingleton<Scheduler.Scheduler>(sp =>
        {
            var config = Get<Configuration.Configuration>(sp);
            return new DefaultScheduler(Log(sp), Get<Job.JobSystem>(sp), Get<Async.Async>(sp), new()
            {
                FixedDt = (float)config.GetDouble("runtime", "fixed_dt", 1.0 / 60.0),
                FixedDtMaxAccum = (float)config.GetDouble("runtime", "fixed_dt_max_accum", 0.25),
            });
        });
        services.TryAddSingleton<Runtime.Runtime>(sp =>
        {
            var config = Get<Configuration.Configuration>(sp);
            return new DefaultRuntime(Log(sp), Get<Ecs.EcsRegistry>(sp), Get<TaskPool.TaskPool>(sp), new()
            {
                FixedDt = (float)config.GetDouble("runtime", "fixed_dt", 1.0 / 60.0),
                FixedDtMaxAccum = (float)config.GetDouble("runtime", "fixed_dt_max_accum", 0.25),
                MaxSystemsPerPhase = (uint)config.GetInt("runtime", "max_systems_per_phase", 256),
            });
        });

        services.TryAddSingleton<Render.Gpu.GpuDevice>(sp => new WebgpuGpuDevice(Log(sp), null, new() { EnableValidation = false, DebugLabels = false }));
        services.AddSingleton(sp => new EngineReadiness(Get<Render.Gpu.GpuDevice>(sp) is WebgpuGpuDevice device ? device.Ready : 0));
        services.TryAddSingleton<Render.Gpu.GpuRenderTarget>(sp =>
        {
            var mailbox = Get<Configuration.Configuration>(sp).GetString("runtime.renderer", "present_mode", "fifo") == "mailbox";
            return new WebgpuWindowGpuRenderTarget(Log(sp), Get<Render.Gpu.GpuDevice>(sp), Get<Window.Window>(sp), new() { PresentMode = mailbox ? GpuPresentMode.Mailbox : GpuPresentMode.Fifo });
        });
        services.TryAddSingleton<Text.FontLoader>(sp => new StbFontLoader(Log(sp), Get<Io.Io>(sp)));
        services.TryAddSingleton<AssetResolver>(sp => new DefaultAssetResolver(Log(sp), null, Get<Text.FontLoader>(sp), root, Get<Io.Io>(sp)));
        services.TryAddSingleton<SceneTree>(sp => new DefaultSceneTree(Log(sp), Get<Ecs.EcsRegistry>(sp)));
        services.TryAddSingleton<InputActions>(sp => new DefaultInputActions(Log(sp), Get<Configuration.Configuration>(sp), new() { Section = "input" }));
        services.TryAddSingleton<NodeTypes>(sp => new DefaultNodeTypes(Log(sp), Get<Scheduler.Scheduler>(sp), Get<Ecs.EcsRegistry>(sp), Get<SceneTree>(sp), Get<InputActions>(sp)));
        services.TryAddSingleton<SceneFiles>(sp => new DefaultSceneFiles(Log(sp), Get<Ecs.EcsRegistry>(sp), Get<NodeTypes>(sp), Get<AssetResolver>(sp), Get<Io.Io>(sp)));
        services.TryAddSingleton<Physics.Physics2D>(sp =>
        {
            var config = Get<Configuration.Configuration>(sp);
            return new Box2DPhysics2D(Log(sp), Get<Job.JobSystem>(sp), new()
            {
                GravityX = (float)config.GetDouble("runtime.physics_2d", "gravity_x", 0.0),
                GravityY = (float)config.GetDouble("runtime.physics_2d", "gravity_y", 0.0),
            });
        });
        services.TryAddSingleton<Audio.Audio>(sp => new MiniaudioAudio(Log(sp), Get<Io.Io>(sp)));

        services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, SceneHierarchyModule>(sp =>
        {
            Get<SceneTree>(sp);
            return new SceneHierarchyModule(Log(sp), Get<Ecs.EcsRegistry>(sp));
        }));
        services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, Physics.PhysicsBody2DModule>(sp => new Physics.PhysicsBody2DModule(Log(sp), Get<Ecs.EcsRegistry>(sp), Get<Physics.Physics2D>(sp), Get<SceneTree>(sp))));
        services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, Audio.SoundModule>(sp => new Audio.SoundModule(Log(sp), Get<Ecs.EcsRegistry>(sp), Get<Audio.Audio>(sp), new() { Root = root })));
        services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, InputActionsEvaluationModule>(sp => new InputActionsEvaluationModule(Log(sp), Get<InputActions>(sp), Get<Input.Input>(sp))));
        services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, Extraction.ExtractionHistoryModule>(sp => new Extraction.ExtractionHistoryModule(Log(sp), Get<Extraction.Extraction>(sp))));
        services.TryAddEnumerable(ServiceDescriptor.Singleton<Module.Module, NodeTypesSystemsModule>(sp => new NodeTypesSystemsModule(Log(sp), Get<NodeTypes>(sp))));

        var shaderDir = Path.Combine(AppContext.BaseDirectory, "shaders");
        services.TryAddSingleton<Render.Gpu.RenderResourceBinder>(sp => new GroupedRenderResourceBinder(Log(sp), Get<Render.Gpu.GpuDevice>(sp), Get<Io.Io>(sp), new() { ShaderDir = shaderDir }));
        services.TryAddSingleton<RenderService>(sp => new DefaultRenderService(Log(sp), Get<Render.Gpu.GpuDevice>(sp), Get<Render.Gpu.GpuRenderTarget>(sp), Get<Ecs.EcsRegistry>(sp), Get<Io.Io>(sp), Get<Render.Gpu.RenderResourceBinder>(sp), new()
        {
            ShaderDir = shaderDir,
            ColorFormat = GpuTextureFormat.Rgba16Float,
            DepthFormat = GpuTextureFormat.D32Float,
            ClearColor = DefaultRenderer.ClearColor(Get<Configuration.Configuration>(sp)),
        }));
        services.TryAddSingleton<ViewSpace>(sp => new RhViewSpace(Log(sp)));
        services.TryAddSingleton<RenderCamera>(sp => new DefaultRenderCamera(Log(sp), Get<ViewSpace>(sp), Get<Render.Gpu.GpuDevice>(sp)));
        services.TryAddSingleton<RenderSceneResolve>(sp => new DefaultRenderSceneResolve(Log(sp), Get<Runtime.Runtime>(sp), Get<Ecs.EcsRegistry>(sp), Get<RenderService>(sp)));
        services.TryAddSingleton<RenderFrame>(sp => new DefaultRenderFrame(Log(sp), Get<Runtime.Runtime>(sp), Get<Ecs.EcsRegistry>(sp), Get<RenderService>(sp), Get<RenderCamera>(sp), Get<RenderSceneResolve>(sp)));
        var defaultFont = Path.Combine(AppContext.BaseDirectory, "assets", "fonts", "LiberationSans-Regular.ttf");
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IEnginePart, DefaultRenderer>(sp => new DefaultRenderer(sp, defaultFont)));
        return services;
    }
}
