@echo off
for %%I in ("%~dp0..") do set "KE_ROOT=%%~fI"
if not defined ZIG_LOCAL_CACHE_DIR set "ZIG_LOCAL_CACHE_DIR=%KE_ROOT%\build\zig-cache"
zig c++ -target x86_64-windows-gnu %*
