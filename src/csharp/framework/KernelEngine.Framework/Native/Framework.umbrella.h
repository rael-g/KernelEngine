// Binding-generation input only — NOT engine API.
// Pulls every framework-domain header into a single translation unit so
// ClangSharp's --traverse can emit them. The C kernel API has no such
// umbrella; this file lives beside Framework.rsp and is consumed only by it.
#pragma once
#include <kernel_engine/framework/components.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/framework/world.h>
#include <kernel_engine/framework/input_actions.h>
#include <kernel_engine/framework/scene_loader.h>
#include <kernel_engine/framework/world_create.h>
#include <kernel_engine/framework/scene_tree_create.h>
#include <kernel_engine/framework/scene_loader_create.h>
#include <kernel_engine/framework/input_actions_create.h>
#include <kernel_engine/framework/asset_resolver_create.h>
