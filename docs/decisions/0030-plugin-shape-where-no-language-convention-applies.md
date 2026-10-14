# 0030. The shape of a plugin where no language convention applies

Date: 2026-10-13

## Context

Each language is written to its own convention (record 0025), but no convention of Zig or C# says
what the state of a plugin is called or how a slot function is named. A survey of every plugin found
several answers to each question living side by side, and two written rules that the code did not
follow.

## Decision

Where the language is silent the project picks the form the Zig style guide comes closest to, and
otherwise the one most of the code already has.

- The entry file of a plugin is named after the domain and the plugin; a render pass ends in module.
- The state of a plugin is a struct named `State`: the file is its namespace. It embeds the vtable
  as the field `api`, whose handle points back at it, and one function named `stateOf` recovers it
  from the first argument of a slot.
- A slot function is a camelCase verb named after its slot. A prefix is added only in a file that
  implements several vtables.
- A slot begins by refusing a null first argument. A slot without a result ignores it silently; a
  slot with a result reports an invalid argument. A slot that receives an error lane fills it on
  every failure.
- A factory is declared with export and no pub, takes a params struct in which zero selects the
  default, and returns the zeroed handle, held in a local named `empty`, after freeing everything it
  took.
- C types reach a plugin through one file of imports, and shared Zig source by module name.
- A test is named by a sentence stating the behaviour; test doubles come from the shared stubs; the
  last test of a plugin checks that nothing leaked.
- On the managed side a module is named in PascalCase with no dot, a command line tool exits with 0,
  1 for a failure and 2 when it could not run.

## Consequences

- The rule that named the state struct after the plugin and the slot functions with a plugin prefix
  is replaced.
- The code that departs from these is debt; each item enters the gate of engine rules with a ceiling
  as it is taken up.
- Not made rules: the literal text of an error message, a pair of registration overloads, and what a
  managed value wrapper does over an invalid handle.
