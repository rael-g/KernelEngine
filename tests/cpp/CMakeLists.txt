# This directory used to build test_asset_logic, which compiled the assimp
# plugin's C++ converter and texture decoder straight into a gtest binary. That
# implementation is Zig now and its unit coverage moved with it — see the
# `asset_assimp_zig_tests` entry in src/zig/asset/assimp, which builds the same
# fixtures against Assimp's C API.
#
# test_task_scheduler.cpp is still here and still unwired: no target has ever
# built it. Wiring it up is its own task rather than part of this migration, so
# it is left in place instead of being quietly dropped.
