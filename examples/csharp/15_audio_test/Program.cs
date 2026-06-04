using KernelEngine.Audio.MiniAudio;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// ── 15 Audio Test ─────────────────────────────────────────────────────────────
// Validates the audio pipeline (kernel ke_audio contract → miniaudio plugin → C# IAudio).
// Short sine-wave beeps are generated to temp WAVs at startup (no committed binary assets).
// Click the window to give it focus, then:
//   • Space  → play the beep
//   • L      → toggle a 220 Hz looping bass note
//   • Escape → quit

var services = new ServiceCollection()
    .AddKernel().AddNativeFramework()
    .AddLogger().AddConsoleSink()
    .AddInput()
    .AddGlfwWindow(640, 200, "KernelEngine — 15 Audio Test (click window, then Space)")
    .AddBgfxRenderer(System.IO.Path.Combine(AppContext.BaseDirectory, "shaders"))
    .AddMiniAudio();

using var app = new Application();

var beepPath = WriteSineWav(440, durationMs: 150);
var bassPath = WriteSineWav(220, durationMs: 500);

app.OnReady = (_) =>
{
    var audio = app.Services.GetRequiredService<IAudio>();
    var beep  = audio.LoadSound(beepPath);
    var bass  = audio.LoadSound(bassPath);
    Console.WriteLine($"[Audio] beep={beep.Value} bass={bass.Value}");

    app.Tree.AddNode(new AudioController(audio, beep, bass), "AudioController");
    return System.Threading.Tasks.Task.CompletedTask;
};

app.OnUpdate = (tree, _) => tree.ClearColor(0.05f, 0.08f, 0.1f, 1f);

app.Run(services);

// ── WAV synthesis (must come before any type declaration) ─────────────────────

static string WriteSineWav(int frequency, int durationMs)
{
    const int sampleRate = 44100;
    int numSamples = sampleRate * durationMs / 1000;
    int dataSize = numSamples * 2; // 16-bit mono

    var path = Path.Combine(Path.GetTempPath(), $"ke_audio_{frequency}hz_{durationMs}ms.wav");
    using var fs = new FileStream(path, FileMode.Create, FileAccess.Write);
    using var w = new BinaryWriter(fs);
    w.Write(System.Text.Encoding.ASCII.GetBytes("RIFF"));
    w.Write(36 + dataSize);
    w.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt "));
    w.Write(16);
    w.Write((short)1);  // PCM
    w.Write((short)1);  // mono
    w.Write(sampleRate);
    w.Write(sampleRate * 2);
    w.Write((short)2);
    w.Write((short)16);
    w.Write(System.Text.Encoding.ASCII.GetBytes("data"));
    w.Write(dataSize);

    double envSamples = sampleRate * 0.010;
    for (int i = 0; i < numSamples; i++)
    {
        double t = (double)i / sampleRate;
        double env = Math.Min(1.0, Math.Min(i / envSamples, (numSamples - i) / envSamples));
        short sample = (short)(env * 8000 * Math.Sin(2 * Math.PI * frequency * t));
        w.Write(sample);
    }
    return path;
}

// ── Behaviour ─────────────────────────────────────────────────────────────────

sealed class AudioController(IAudio audio, SoundHandle beep, SoundHandle bass) : Node
{
    private bool _bassLooping;

    protected override void OnInput(ref InputEvent evt)
    {
        if (evt.Kind != InputEventKind.KeyDown) return;
        switch (evt.Key)
        {
            case Key.Space:
                audio.Play(beep, volume: 0.6f);
                Console.WriteLine("BEEP");
                break;
            case Key.L:
                _bassLooping = !_bassLooping;
                if (_bassLooping) { audio.Play(bass, volume: 0.4f, loop: true); Console.WriteLine("BASS on"); }
                else              { audio.Stop(bass);                            Console.WriteLine("BASS off"); }
                break;
            case Key.Escape:
                Environment.Exit(0);
                break;
        }
    }
}
