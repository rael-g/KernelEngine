// Single translation unit ClangSharp processes for this domain: the audio
// contract plus its scene-component vocabulary. Mirrors Render.umbrella.h —
// a domain whose bindings span more than one header needs one file to include
// them, since the generator takes a single --file.
#include <kernel_engine/audio/audio.h>
#include <kernel_engine/audio/components.h>
