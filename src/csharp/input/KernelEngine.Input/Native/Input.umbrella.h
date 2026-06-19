// Binding-generation input only — NOT engine API.
// Pulls every input-domain header into a single translation unit so
// ClangSharp's --traverse can emit them. The C kernel API has no such
// umbrella; this file lives beside Input.rsp and is consumed only by it.
#pragma once
#include <kernel_engine/input/key.h>
#include <kernel_engine/input/snapshot.h>
#include <kernel_engine/input/event.h>
#include <kernel_engine/input/input.h>
