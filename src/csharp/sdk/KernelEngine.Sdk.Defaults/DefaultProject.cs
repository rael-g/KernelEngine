using KernelEngine.Assembly;
using KernelEngine.Assembly.Default;
using KernelEngine.Assembly.Toml;
using KernelEngine.Configuration;
using KernelEngine.FileSystem;
using KernelEngine.FileSystem.Std;
using KernelEngine.Part.Native;

namespace KernelEngine;

/// <summary>
/// A project directory opened for an engine: a file system rooted there and its <c>Project</c> file loaded into a
/// configuration, with the shader directory and the default font beside the executable set where the binder, the
/// service and the labels read them.
/// </summary>
public sealed unsafe class DefaultProject : IDisposable
{
    delegate ke_part* PartsOf(nuint* count);

    static readonly PartsOf[] s_libraries =
    [
        Job.Enki.Native.NativeMethods.job_system_enki_parts, Async.Enki.Native.NativeMethods.async_enki_parts,
        Io.Std.Native.NativeMethods.io_std_parts, Input.Native.NativeMethods.input_default_parts,
        Ecs.Flecs.Native.NativeMethods.ecs_flecs_parts, Schedule.Native.NativeMethods.schedule_parts,
        Scheduler.Native.NativeMethods.scheduler_parts, Framework.Native.NativeMethods.framework_parts,
        EngineNodes.Native.NativeMethods.engine_nodes_parts, Physics.Box2D.Native.NativeMethods.physics_2d_box2d_parts,
        Physics.Native.NativeMethods.physics_body2d_parts, Extraction.Native.NativeMethods.extraction_default_parts,
        Window.Glfw.Native.NativeMethods.window_glfw_parts, Render.Webgpu.Native.NativeMethods.gpu_device_webgpu_parts,
        Render.Webgpu.Native.NativeMethods.render_binder_grouped_parts, Render.Webgpu.Native.NativeMethods.render_service_parts,
        RenderGraph.Simple.Native.NativeMethods.render_graph_simple_parts, View.Native.NativeMethods.view_space_parts,
        Render.Webgpu.Native.NativeMethods.render_camera_parts, Render.Webgpu.Native.NativeMethods.render_scene_parts,
        Render.Frame.Native.NativeMethods.render_frame_parts, Render.Webgpu.Native.NativeMethods.render_gbuffer_parts,
        Render.Webgpu.Native.NativeMethods.render_deferred_lighting_parts, Render.Webgpu.Native.NativeMethods.render_forward_parts,
        Render.Webgpu.Native.NativeMethods.render_tonemap_parts, Render.Webgpu.Native.NativeMethods.render_ui_parts,
        Text.StbTrueType.Native.NativeMethods.text_stb_truetype_parts, Audio.MiniAudio.Native.NativeMethods.audio_miniaudio_parts,
        Audio.Native.NativeMethods.audio_module_parts, Runner.Window.Native.NativeMethods.runner_window_parts,
    ];

    /// <summary>Opens the project in <paramref name="projectDir"/>.</summary>
    /// <param name="projectDir">The directory holding the project file, its scenes and its assets.</param>
    public DefaultProject(string projectDir)
    {
        Files = new StdFileSystem(projectDir);
        Configuration = new DefaultConfiguration();
        using (var source = new ConfigurationTomlConfigurationSource(Files)) source.Load(Configuration, Path.Combine(projectDir, "Project"));
        var shaders = Path.Combine(AppContext.BaseDirectory, "shaders");
        Configuration.SetString("binder", "shader_dir", shaders);
        Configuration.SetString("service", "shader_dir", shaders);
        Configuration.SetString("labels", "default_font", Path.Combine(AppContext.BaseDirectory, "assets", "fonts", "LiberationSans-Regular.ttf"));
    }

    /// <summary>The file system rooted at the project directory.</summary>
    public FileSystem.FileSystem Files { get; }

    /// <summary>The project file's values, each instance's section among them.</summary>
    public Configuration.Configuration Configuration { get; }

    /// <summary>
    /// Makes an assembly over <see cref="Configuration"/> with <see cref="Files"/> as the external
    /// <c>file_system</c>, the parts of every default library, and the default composition over them, the file
    /// <c>defaults.composition</c> beside the executable. The assembly keeps the project's objects alive.
    /// </summary>
    public KernelEngine.Assembly.Assembly Open()
    {
        var assembly = new DefaultAssembly(Configuration);
        try
        {
            assembly.Hold(((INativeConfiguration)Configuration).Owner);
            assembly.Hold(((INativeFileSystem)Files).Owner);
            assembly.AddExternal("file_system", "ke_file_system", (nint)((INativeFileSystem)Files).Native);
            foreach (var library in s_libraries)
            {
                nuint count = 0;
                var parts = library(&count);
                for (nuint i = 0; i < count; i++) assembly.AddPart((nint)(parts + i));
            }
            using var composition = new AssemblyTomlCompositionSource(Files);
            composition.Load(assembly, Path.Combine(AppContext.BaseDirectory, "defaults.composition"));
            return assembly;
        }
        catch
        {
            assembly.Dispose();
            throw;
        }
    }

    /// <summary>Releases the project's objects; an assembly opened over them keeps them until it is destroyed.</summary>
    public void Dispose()
    {
        Configuration.Dispose();
        Files.Dispose();
    }
}
