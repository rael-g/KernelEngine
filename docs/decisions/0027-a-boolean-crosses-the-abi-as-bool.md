# 0027. A boolean crosses the ABI as bool

Date: 2026-10-13

## Context

A typedef of one byte, ke_bool, was introduced because P/Invoke marshalled a C bool as a four-byte
value. The contracts ended up mixing both: most slots return bool. Every binding assembly now
disables runtime marshalling, under which a bool crosses as one byte unchanged.

## Decision

The contracts use `bool`. The typedef is retired once a gate pins the disabled marshalling on every
binding assembly.

## Consequences

- The headers follow the convention of C.
- A binding assembly without the attribute would misread a boolean, which is why the gate comes
  first.
- Until the retirement is done the headers hold both spellings.
