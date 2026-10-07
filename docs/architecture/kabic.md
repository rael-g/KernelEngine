# How does kabic turn a C header into C#, Zig and C, and what stops it going wrong?

kabic is the generator under `src/csharp/kabic/`. It reads the contract headers in `src/c/` and the
factory headers in plugins' `include/`, keeps what their doc comments say, and writes a projection
per target language. Nothing it emits is edited by hand; the headers are the only source.

```
header.h --zig cc ast-dump--> Kabic.Frontend --> ke_api.json --> Kabic.Core (Classifier)
                                                                    |--> Kabic.CSharpBackend --> *.g.cs
                                                                    |--> Kabic.ZigBackend    --> <domain>.zig
                                                                    '--> Kabic.CBackend      --> component_fields.h
```

## What it reads

`Kabic.Pipeline.Extraction` writes one throwaway translation unit that `#include`s the domain's headers
and runs `zig cc -Xclang -ast-dump=json -fsyntax-only -fparse-all-comments` over it
(`Extraction.cs:28`, `:79`). A header that fails to parse stops the run
(`Extraction.cs:95`). `Kabic.Frontend.Extractor` keeps only nodes from the listed files
(`Extractor.cs:19-36`):

| input | what is kept |
|---|---|
| `headers` | every enum, complete struct, `ke_*` function with a symbol, and typedef (`Extractor.cs:46-67`) |
| `--aux` | typedefs only (`Extractor.cs:42`) |
| `--compose` | enums, structs and typedefs, marked `External` so the domain that owns them still emits them (`Extractor.cs:44-53`; `ApiModel.cs:51`, `:76`) |

A `static` function is dropped: it leaves no symbol to bind (`Extractor.cs:56`, `:234`). A struct
holding function pointers becomes a vtable whose slots drop parameter 0, kept as `Receiver`
(`Extractor.cs:120-165`). A typedef of a function pointer becomes a callback described lane by lane
(`Extractor.cs:65`, `:178`). A typedef onto a C primitive lands in `type_aliases`
(`Extractor.cs:60-64`).

## What a doc comment says: the tags

Meaning that C types cannot carry is written in the doc comment, as bracketed tags at the front of a
`@param` block, a `@return` block, a field, or a struct or enum summary: `[out,array_of:count]`.
`DocParser.Parse` peels leading `[a,b:c]` blocks off the text and splits each on commas
(`DocParser.cs:9`, `:49-55`); `ApiParam.Has` and `TagValue` match `name` or `name:value`
(`ApiModel.cs:6-7`). A `@param` naming something that is not a parameter fails extraction
(`Extractor.cs:147`, `:246`; `Extraction.cs:42-44` raises them all as one failure).

A tag exists in a backend only if that backend names it, and a backend ignores the rest: the Zig
backend never reads `[rooted]` (`grep -c rooted Kabic.ZigBackend/ZigBackend.cs` prints `0`). The
tags that decide a call's *shape* are read once, in `Classifier`:

| tag | where it goes | what it means |
|---|---|---|
| `[out]` | param | written back by the callee (`Classifier.cs:254`) |
| `[try]` | slot summary | a `false` return means not found: the C# backend projects `Try<Name>(..., out x)`, the Zig backend `?T` (`Classifier.cs:205`, `CSharpBackend.cs:2297-2306`, `ZigBackend.cs:621-623`) |
| `[array_of:n]` | param, or the `@return` | pointer whose length is parameter `n`; on a return, the returned pointer is counted by `n` (`Classifier.cs:208-217`, `:240-252`) |
| `[bytes_of:n]` | `void *` param | opaque payload bounded by byte count `n` (`Classifier.cs:219-238`) |
| `[expand]` | param to a `_params` struct | the struct's fields stand in for the parameter (`Classifier.cs:162-179`) |
| `[rooted]` | written-back `void **` | the pointer is stored, never dereferenced, by the native side (`Classifier.cs:256-262`) |
| `[lifecycle:init]`, `[lifecycle:shutdown]` | slot summary | the slot a wrapper calls after create or before destroy (`Classifier.cs:115-118`) |
| `[callback]` | param | the parameter's type is a vtable the caller implements (`Classifier.cs:96-101`) |

`[default:...]`, `[name:...]`, `[bool]` and `[output]` on a component field are read by the C
backend (`CBackend.cs:94`, `:60`, `:148`, `:157`). The C# backend reads further tags that no other
backend does (`enum`, `node`, `base`, `closure`, `completion`, `view`, `value`, `borrowed`, `utf8`, `idiom`, and
others, all as `.Has("...")` / `.TagValue("...")` in `CSharpBackend.cs`), and the Zig backend reads
`utf8`, `closure`, `default` and `optional` itself (`ZigBackend.cs:568`, `:723`, `:858`, `:333`).

## `ke_api.json`

The frontend's output is one committed file per domain, at the manifest's `apiJson` path (for
example `src/csharp/render/ke_api.json`). Its top-level keys are `enums`, `structs`, `vtables`,
`functions`, `callbacks` and `type_aliases` (`Serialization.cs:8-17`). Every backend starts from
`ApiReader.Read` on that file, never from a header (`ApiModel.cs:130-197`), so the file is the whole
of what a backend can know.

`scripts/api_domains.json` is the hand-written manifest. Each entry of `domains` names the
`headers`, `includeDirs`, `apiJson`, the C# `namespace` and `nativeNamespace`, the `outDir`, and
optionally `abstractionsOutDir`, `usings`, `library`, `auxHeaders`, `composeHeaders` and `cOut`
(the C field-table target). `kabic generate` walks it in one process: it extracts every domain in parallel
(`Regeneration.ExtractAll`), then generates the C# and, for entries with `cOut`, the C field table
(`Regeneration.GenerateOne`, `Regeneration.cs:31-38`).

## The Classifier

`Classifier.Classify(model, explicitProviders, explicitCallbacks, convention)` (`Classifier.cs:88`)
decides what each struct is and what shape each slot has. A `Convention`, built by `ConventionBuilder` (its
source is the `convention` object of `api_domains.json`, `Convention.Load`), holds the project's spellings, so the
classifier states nothing about `ke_`. A failure kind is declared with `AddError(singleton, nativeName, managed, zig)`:
the Zig error set and the generated `NativeErrors.Kinds.g.cs` both come from that list, and the error header only
has to export each singleton:

- a vtable is a struct with slots that is not a handle (`_handle`) and not a parameter bag
  (`_params`); it is a *provider* when a `<name>_handle` struct or a `<name>_create` function exists
  (`Classifier.cs:93`, `:105-110`);
- a slot is *fallible* when its last parameter is `ke_error**` (`Convention.IsErrorOutParam`); the parameter
  is removed from the projected signature (`Classifier.cs:196-197`);
- the resulting `SlotShape` is one of `Fallible`, `Try`, `ReturnsOutParam`, `TupleOutParams`,
  `Plain` (`Classifier.cs:4`, `:286-290`);
- a free function whose first parameter is a described struct is grouped under it and classified
  with the same rules as a slot (`Classifier.cs:139-152`).

A description the classifier cannot classify throws `InvalidOperationException` and the whole domain
fails: a slot that answers, fails and writes a value (`Classifier.cs:293-298`), an unmatched
`array_of` or `bytes_of` name, two written-back parameters that would project under one name.

## The three backends

| backend | driver | emits | when it cannot render a form |
|---|---|---|---|
| `Kabic.CSharpBackend` | `Kabic.Pipeline.Generation.CSharp` | enums, value structs, views, providers with a contract interface, callback interfaces, node types, free-function groups (`Generation.cs:21-115`) | throws `InvalidOperationException`; no catch, so the domain run fails |
| `Kabic.ZigBackend` | `kabic zig` | one module per domain that declares the ABI itself in a `pub const abi = struct`, with no `@cImport` line (`ZigBackend.cs:91-92`) | a slot it cannot render raises `NotSupportedException`, is caught per slot (`ZigBackend.cs:497`) and listed in the module's header comment (`ZigBackend.cs:110-115`); the other slots are still emitted |
| `Kabic.CBackend` | `Kabic.Pipeline.Generation.CFieldTable` | a `ke_component_field` table per component struct (`_component` suffix), as `offsetof`/`sizeof` expressions the C compiler evaluates (`CBackend.cs:40-50`) | a `[default]` whose component count does not match its field type throws (`CBackend.cs:105-107`) |

The C backend leaves a field out of its tables when the field is `[output]` or has no scene-file
spelling (`CBackend.cs:133`).

The Zig backend refuses a raw callback, an opaque payload, a `[closure]` that names no state
parameter, a consumer vtable with other than one untyped field, and a consumer slot that reports
failure (`ZigBackend.cs:521-524`, `:723-738`, `:804-813`). It learns where a type from another
domain lives by reading the other domains' `ke_api.json` (`ZigCommand.cs`); the manifest
carries no Zig output directory and nothing in `scripts/`, `build.zig` or `ci.yml` calls
`kabic zig`, so no generated Zig is in the tree.

## The gates

Each gate is a `kabic check <name>` command or a file-based `dotnet run scripts/<name>.cs`, and exits non-zero on failure. `ci.yml`
runs all nine through `scripts/verify.cs` (see `docs/conventions/ci.md`).

| gate | what fails it |
|---|---|
| `kabic check drift` | a domain's committed `ke_api.json`, generated C#, or C field table differs byte for byte from a fresh extraction and generation into a temp directory; exits 1 for that. When the extraction or generation itself cannot run it exits 2 and says it compared nothing, because that is a broken tool, not drift |
| `check_abi_layout.cs` | the size, alignment or a member offset of any struct or vtable the contract headers declare differs from `scripts/abi_layout.snapshot`, which a C compiler probe regenerates; an intended change is recorded with `-- --update` |
| `kabic check reconstruction` | any file `kabic generate --into <temp>` produces is missing from the tree or differs from it (`check_reconstruction.cs:38-51`) |
| `kabic check api-coverage` | a public header under `src/c` or `src/zig` is described by no `api_domains.json` entry, no `bindings` entry, and no recorded exclusion (`check_api_coverage.cs:56-67`); a header with only `static inline` functions needs none |
| `kabic check out-params` | a parameter named `out` or carrying the convention's out prefix, other than its failure lane, carries no `[out]` tag |
| `check_generator_contract.cs` | an attribute name kabic emits, the one the source generator matches by string, and the class under `src/csharp/framework` stop agreeing (`check_generator_contract.cs:39-62`) |
| `check_component_fields.cs` | a Zig `component_register` call omits the generated field table for a component that has one, or a table is named by no registration (`check_component_fields.cs:46`, `:75`) |
| `check_managed_handwritten.cs` | the count of hand-written `.cs` files under `src/csharp` (excluding `Generated`, `*.g.cs`, `kabic/`) goes above the ceiling, or stays below it (`check_managed_handwritten.cs:17`, `:35-47`) |
| `kabic check bindings` | what ClangSharp generates from a binding's headers into a temporary directory differs, byte for byte or by file set, from the committed `Generated/` tree |

## The ClangSharp bindings, which are configured from the manifest

The raw P/Invoke layer is a different generator: ClangSharp, used as a library by `Kabic.ClangSharpBackend`
and nothing else. `kabic bindings` reads the `bindings` array of `api_domains.json` (`name`, `project`,
`namespace`, `headers`, `library`, `output`, and optionally `additional` and `macroBindings`) and builds
one configuration per entry in memory (`BindingsPlanner`). It computes the include directories by following
`#include <kernel_engine/...>` transitively from the binding's headers, the traversal list, a remap and an
exclude for every type another reachable binding owns, and an umbrella header under `build/kabic/` when a
binding has more than one header. A header claimed by two bindings fails the run, and a remap into a
project the binding does not reach is never emitted (`Reachable`). The `project` of an entry has to be a
real project directory, since reachability is read from its `.csproj`. `kabic bindings --print-config`
prints what each binding is given without running ClangSharp, and `kabic check bindings` reports every
binding whose committed output differs from what the headers generate. A failing run keeps the previous
output of that binding.
