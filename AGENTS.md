# AGENTS.md

Instructions for coding agents working on Hypoland. `CLAUDE.md` imports this file.

# Hypoland

Hypoland is a fork of Hyprland that targets old GPUs limited to **OpenGL ES 2.0 / OpenGL 2.1**
(Intel Gen4/Gen4.5: GMA X3100 / 965GM, GMA 4500MHD / GM45). Upstream Hyprland requires GLES 3.x.
Hypoland's renderer and shaders are GLES 2.0 / GLSL ES 1.00 only; that port is done and runs on the X200.

## Hardware

- **Dev machine:** this desktop. All editing and compiling happens here.
- **Test machine:** ThinkPad X200 on the same LAN (GM45 / GMA 4500MHD, Core 2 Duo, Mesa `crocus` driver,
  i915 kernel driver). It runs Omarchy 4 on Hypoland from `~/hypoland`. Stock Hyprland fails to start on it
  (no GLES 3) and is still the installed system package; the Hypoland package has not been installed there.
- X200 access: `ssh x200` (ssh config alias -> 192.168.95.91, user `a`, uid 1000, key auth works).
  6 GB RAM, 2 cores, Arch kernel 7.1.x, Mesa 26.2, stock `hyprland` 0.56.2 installed, 100 GB free in `/home`.
- Root on the X200: `ssh root@x200` (key auth). Test tools are installed: `waybar`, `weston-simple-egl`,
  `glmark2-es2-wayland`, `pidstat`, `eglinfo`, `grim`, `foot`.

## Repository

- Repo lives in `/home/jonny/Work/hypoland`. The default branch is `master`.
- Remotes: `origin` = github.com/hegjon/Hypoland (the user's fork, renamed from hegjon/Hyprland),
  `upstream` = hyprwm/Hyprland, `aquamarine` = github.com/hegjon/aquamarine.
- History: `master` is based on the user's commit `5fafec87` on upstream main (v0.56.0+141, formerly the branch
  `gles2-legacy-renderer`),
  which added a GLES2 path chosen at runtime. Hypoland has since removed the GLES3 path and the runtime switch,
  so `m_legacyGLES` and `GLES2ShaderCompat` no longer exist.
- `master` is pushed to `origin`, is the default branch on GitHub and is the only branch there. The 34 branches
  the fork had before (copies of upstream branches, `main`, `gles2-legacy-renderer`) were deleted on 2026-09-27;
  their names and commits are listed in `docs/baseline/removed-branches.txt`.
  Commit and push only when the user asks.
- aquamarine is embedded: `subprojects/aquamarine` is a squashed `git subtree` of
  `hegjon/aquamarine` branch `gles2-support` (remote `aquamarine`). It is built as a static library by
  `cmake/aquamarine.cmake`, not by its own CMakeLists.txt. Its generated `wl_*_interface` symbols are
  weakened with objcopy because the compositor defines the same tables. Update with
  `git subtree pull --prefix=subprojects/aquamarine aquamarine gles2-support --squash`.
- Rename status: binaries are `Hypoland` and `start-hypoland`, with `Hyprland`, `hyprland`, `hypoland` and
  `start-hyprland` installed as symlinks. CMake target names, session file names (`hyprland.desktop`,
  `hyprland-uwsm.desktop`) and the `hyprctl version` text are intentionally unchanged.
- GLES3 code is removed, the renderer is GLES2 only (no runtime switch):
  - Include `src/render/gl/GLES2.hpp` instead of any GLES header. It poisons every GLES3 entry point, so
    using one is a compile error. VAO calls go through `GL_OES_vertex_array_object`, loaded with `eglGetProcAddress`.
  - Shaders in `src/render/shaders/glsl` are native GLSL ES 1.00 (`#version 100`). There is no runtime translator.
    Color management, tonemapping, ICC, mirror and motion blur code is gone from the shaders; `color.glsl` keeps
    only the sRGB / gamma 2.2 transfer functions that gradients need.
  - Blur variants ripple, water, fluid_jar, prism and acrylic are removed and fall back to dual Kawase.
  - The embedded aquamarine is patched in-tree the same way (GLES2 context and ES 1.00 shaders only). It also
    creates its DRM renderer for the primary GPU only when a secondary GPU needs it.
  - Framebuffers have one color attachment. The stencil is a `GL_STENCIL_INDEX8` renderbuffer per framebuffer
    (GLES2 has no packed depth/stencil texture); blur needs it for `ignore_alpha`.
  - Removed as dead code: the color management render paths and protocol (`wp_color_manager_v1` is not
    advertised), the ICC 3D LUT, FP16 work buffers, the mirror texture (second color attachment), motion blur and
    `hyprpm/`. Their config options are still registered and ignored.
  - Kept: the image description types in `src/helpers/cm/` and the KMS side in `Monitor.cpp` /
    `handleFullscreenSettings()` (HDR metadata, CTM, wide gamut). They are inert, because every output is forced
    to sRGB in `applyMonitorRuleSoft()`. ICC profiles still apply their VCGT gamma ramps through KMS.
- The config is Lua in this Hyprland version (`~/.config/hypr/hyprland.lua`, Omarchy uses it). With a Lua config
  `hyprctl keyword` answers `unknown request`; use `hyprctl eval "hl.config({...})"`.
- Both machines have identical hypr* library versions (hyprutils 0.14.2, hyprlang 0.6.8, hyprcursor 0.1.13,
  hyprgraphics 0.5.1), so a desktop build links cleanly on the X200. Keep them in sync. The system aquamarine
  is not used.
- Logo: `assets/logo/` (a potato: `hypoland.svg`, `hypoland-mono.svg`, `header.svg`, PNG exports).
  The README uses the pre-2000 style banner `assets/logo/retro/header-retro.svg` (bitmap lettering
  whose O is a pixel potato hanging below the baseline, since hypo- means "under"), generated with
  `scripts/logo/retro.py scripts/logo/potato-mask.txt assets/logo/retro`. The Hyprland banner and screenshots
  were removed from `assets/`.
- Baseline failure of stock Hyprland 0.56.2 is saved in `docs/baseline/stock-hyprland-0.56.2-crash.txt`:
  `eglCreateContext failed with both GLES 3.2 and GLES 3.0` (EGL_BAD_MATCH), then an assert in
  `CHyprOpenGLImpl::CHyprOpenGLImpl()`. Aquamarine's own `CDRMRenderer` also wants GLES 3, but that is
  only needed for multi-GPU and its failure is non-fatal.

## Hard constraints

- Renderer: GLES 2.0 only. Shaders in GLSL ES 1.00. No instancing, integer textures, MRT, or GLES 3 features.
- Build for baseline `x86-64`. Never use `-march=native` (the desktop CPU is far newer than the X200's).
- License: Hyprland is BSD-3. Keep upstream copyright notices and LICENSE. Don't use Hyprland's logo or imply endorsement.

## Compatibility requirements (do not break)

Rename only the binary and branding. When renaming, do NOT touch:
- Config path: `$XDG_CONFIG_HOME/hypr/hyprland.lua` (this Hyprland version is configured in Lua) and `--config`.
- IPC sockets: `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock` and `.socket2.sock`.
- The `HYPRLAND_INSTANCE_SIGNATURE` env var, IPC command names, JSON output format, and event names.
- `XDG_CURRENT_DESKTOP=Hyprland` (needed by xdg-desktop-portal-hyprland and app detection).
- Hyprland Wayland protocols used by Quickshell (Omarchy's shell): focus grab, global shortcuts, toplevel export.

Removed features must stay **registered as no-op config options** (warn once, never error), so existing
configs such as Omarchy's load without the red error bar. Setting a removed option at runtime must return `ok`
(`hyprctl eval "hl.config({...})"`; `hyprctl keyword` is answered with `unknown request` by upstream when the
config is Lua, which is not something Hypoland changed).

Ship `hyprctl` built from this fork so versions match. The Arch package should declare
`provides=('hyprland')` and `conflicts=('hyprland')`.

## Features to remove or default off

Remove/rewrite (GPU heavy): color management / HDR pipeline, screen shaders, per-window offscreen rendering
where avoidable. Done so far: color management is removed from the renderer, the shaders and the protocols.
Screen shaders and shadows (default off) are still in the code; screen shaders written for Hyprland are
GLSL ES 3.00 and do not compile here.

Keep: blur (dual Kawase and the GLES2-capable variants), default off. Decided by the user on 2026-09-27 after
measuring it on the X200: about 1% extra compositor CPU and 57-60 fps. Do not remove it.

Optional, default off: animations (keep short slides only, no fades), animated/gradient borders,
rounded corners (radius 0 must skip the shader path), dim inactive, inactive opacity, fractional scaling.

CPU/RAM: drop the plugin system and hyprpm; default to XCursor over hyprcursor SVG; keep Xwayland optional.
Done so far: hyprpm is removed and hyprcursor is off by default. The plugin system is removed (2026-09-27): plugins
must be built against the exact Hyprland source they load into and most draw with GLES3 era renderer code, so
keeping up was not worth it. `hl.plugin.load()` warns once and does nothing, `hl.get_loaded_plugins()` is empty,
`hyprctl plugin list` answers `no plugins loaded` / `[]`, `plugin load` / `unload` fail, and `hyprctl version`
still prints the ABI hash. No symbols are exported, udis86 is gone and no headers or `hyprland.pc` are installed.
The binary shrank from 21.3 to 18.5 MB. hyprtester lost the test plugin that injected input, so the tests that
needed it (keybinds, gestures, drag, snap and the input clients) are removed.

Keep (they help): damage tracking, direct scanout, hardware cursor planes.

Prefer compile-time flags (e.g. `-DNO_ANIMATIONS`) so removed code isn't built.

## Testing workflow

1. Build on the desktop, `rsync` into a prefix on the X200 (e.g. `~/hypoland/`). Never touch system packages.
2. X200 autologins on tty1 into a loop script that runs `~/hypoland/bin/Hypoland` and restarts it on exit
   (a compositor started over SSH can't take the display). Restart with `pkill Hypoland`.
   Do not reboot for recovery, see the pitfalls below.
3. Over SSH, with `XDG_RUNTIME_DIR=/run/user/<uid>` set:
   - control: `hyprctl`
   - screenshots: `grim`, then `scp` back and inspect the image
   - clients: `foot`, `weston-simple-egl`, `glmark2-es2-wayland`
   - resources: `pidstat`, `ps -o rss` (`intel_gpu_top` is unreliable on Gen4)
   - logs: `$XDG_RUNTIME_DIR/hypr/*/hyprland.log` (mostly empty, Omarchy disables logs), the compositor's
     stderr in `~/hypoland/loop.log`, crash reports in `~/.cache/hyprland/`
4. Wrap steps 1-3 in one script, `./test-x200.sh`, that prints a short pass/fail summary and the log tail.
   Prefer running this script over improvising SSH commands.
5. Fast local checks: run nested on the desktop with `LIBGL_ALWAYS_SOFTWARE=1 MESA_GLES_VERSION_OVERRIDE=2.0`.
   This is NOT a faithful GM45 test (llvmpipe allows extra features); the X200 is the final judge.
6. Quickshell (Omarchy's shell) works on the X200 with GPU rendering. Waybar is installed as a simpler
   layer-shell client for isolating problems.

## Testing pitfalls (learned the hard way)

- **Never reboot the X200** (no `sudo reboot`, no `systemctl reboot`, no `test-x200.sh --reboot`) unless the user
  is present and says so: the disk is encrypted and the password must be typed at boot. For a GPU hang, restart
  the compositor or `getty@tty1` instead and report it.
- `scripts/x200/setup-root.sh` has been applied (2026-09-27): SDDM is disabled, tty1 autologins user `a`, whose
  `~/.bash_profile` starts `~/hypoland/run-loop.sh`. `sudo reboot` is passwordless for `a`, and `ssh root@x200` works.
  Restart the compositor with `pkill -x Hypoland`. If the loop itself dies: `ssh root@x200 systemctl restart getty@tty1`.
  Undo with `setup-root.sh --undo`.
- llvmpipe accepts GLSL that real GLES2 rejects (e.g. a leftover `in` declaration). A shader change is only
  verified once the X200 log has no `Failed to link shader` line and the screenshot shows windows.
- Embedded shader sources (`src/render/shaders/*.inc`) are generated at configure time, so re-run cmake
  configure after editing a shader. `test-x200.sh` does this.
- `~/hypoland/test.lua` on the X200, if present, is used as the config by the loop instead of the Omarchy config.
- Screenshots need frames. With the panel off (DPMS, idle) nothing renders: `grim` blocks or shows stale content.
  The same applies to nested runs on the desktop when its monitor is off or the nested window is not visible.
- Wrap every remote `hyprctl` / `grim` in `timeout`.
- Omarchy's shell starts a fullscreen screensaver (terminal with class `org.omarchy.screensaver`) after 150 s
  without input and locks the session after 300 s (`~/.config/omarchy/shell.json`, `idle`). Nothing types on
  the X200 during tests, so any run longer than 2.5 minutes after a compositor start can end up measuring the
  screensaver or a lock screen. Keep profiling runs short after a restart, check `hyprctl clients` for the
  screensaver class and `solitaryBlockedBy` for `lock`, and look at `journalctl --user | grep "omarchy idle"`.

## Status (2026-09-27)

The first milestone is reached: the GLES2-only build runs the full Omarchy session on the X200 (Quickshell bar,
wallpaper, notifications, windows, Xwayland, Chromium). `./test-x200.sh` passes, including a check that the
window is really drawn (the test terminal fills itself with magenta and the screenshot is checked for it).

Measured on the X200 (1280x800, Omarchy config):
- idle compositor CPU 0%, RSS about 100 MiB (about 73 MiB of it are file mappings, mostly Mesa and LLVM)
- `weston-simple-egl` 60 fps, compositor 8-9% CPU; blur on costs about 1% more
- 4 windows with rounding, shadows, blur, opacity, dim and animations: 58-60 fps, compositor 12% CPU
- `glmark2-es2-wayland` score 127; glxgears through Xwayland 30 fps
- Chromium falls back to software rendering (it wants GLES3 itself); compositor 25% CPU uploading its shm frames

Findings worth keeping:
- `quirks:skip_non_kms_dmabuf_formats` must default to false. Gen4 primary planes have no alpha formats, so with
  the upstream default no client gets an EGL config with alpha and Quickshell's fullscreen overlay turns black.
- Omarchy 4 locks with its Quickshell shell, `hyprlock` / `hypridle` are not installed.
- Defaults changed: blur, shadows, animations and hyprcursor off; logo background and splash are gone
  (`misc:disable_hyprland_logo` is a no-op); hyprpm is removed.
- Packaging: `packaging/arch/PKGBUILD` builds from the working tree (`makepkg -f`).

Tools:
- `HYPOLAND_PROFILE_PASS=1` times every render pass element on the GPU (glFinish) and prints per-type totals to
  stderr every 120 frames. On the X200 put it in `~/hypoland/env` (sourced by the loop), read `~/hypoland/loop.log`.
  It slows rendering down, remove the env file afterwards.
- `debug:overlay` works and shows frame and render times.
- `scripts/x200/kmsgrab.c` (installed on the X200 as root: `/usr/local/bin/hypoland-kmsgrab out.ppm`) saves the buffer
  the display scans out. Use it to check what really reaches the screen: a `grim` screenshot counts as screen
  sharing, which makes the compositor use the work buffer copy path instead of direct rendering. The read takes
  about 80 ms and the compositor draws into that buffer again a few frames later, so an animating client can
  show up half drawn in the capture; freeze it (`pkill -STOP`) for exact results.
- `./bench-x200.sh <label>` measures a change on the normal build: memory 60 s after the start and after the
  workloads, CPU time of the five workloads of `profile-x200.sh`, three rounds, into
  `test-results/bench-<time>-<label>/values.txt`. `./bench-x200.sh --compare <dir> <dir>` prints the difference.
  It runs with the `performance` governor, so its CPU numbers are lower than the ones below (GPU client 3.7%
  instead of 7-10%). The brief for unattended optimization runs is `docs/overnight-ram-cpu.md`.
- `HYPOLAND_NO_DIRECT_RENDER=1` makes every frame go through the work buffer, for comparing the two paths.

Performance (X200, `HYPOLAND_PROFILE_PASS`, GPU time per frame, 4 windows plus a 60 fps client):

| | before 2026-09-27 evening | now |
|---|---|---|
| full-screen redraw | 19.1 ms (pass 14.3 + clear 1.4 + copy 3.4) | 14.4 ms |
| small updates | 3.4 ms (pass 1.7 + clear 1.4 + copy 0.3) | 1.7 ms |

- Every frame used to clear the whole 1280x800 work buffer (1.4 ms, Gen4 has no fast clear). Now only the damage
  is cleared: the pass paints the background over its damage anyway (`clearRegionAfterInvalidation()`).
- Frames are drawn straight into the screen buffer when nothing needs the work buffer (no zoom, no rotated output,
  no screen shader, no mirror or screen sharing), `CHyprOpenGLImpl::canRenderDirectly()`. That removes the copy
  from the work buffer to the screen. Screen buffers are imported twice: as a renderbuffer to render into and as a
  texture to sample from (blur), with a stencil renderbuffer. The screen buffer holds the frame from bufferAge
  frames ago and the damage covers everything since, so blur samples correct pixels outside the damage.
- Fill rate is the limit: one fullscreen 1280x800 blended surface costs about 3.3 ms.
- Borders cost about 0.4 ms per window on a full redraw, they are already limited to the border ring.
- Omarchy gives every window an opacity rule (`default-opacity` tag), so no window occludes the wallpaper.
  With opaque windows the occlusion pass skips what is underneath.
- Quickshell's notification overlay is a transparent fullscreen layer that is blended over every damaged area.

CPU profile: run `./profile-x200.sh`. It builds with frame pointers in `build-prof`, deploys, switches the
Omarchy screensaver and idle lock off, records five workloads with `perf` as root, prints the report to
`test-results/profile-*/profile.txt` and puts the normal build back. Use `--keep` to leave the profiling build
on the X200; `perf report` on the saved data only resolves symbols while that build is installed.
Findings:
- Idle desktop: 0.1% CPU.
- GPU client at 60 fps, 10% CPU: `renderMonitor` 76% of it. `endRender` 52% (of which `CEGLSync::create` 25%,
  this is where the driver flushes and submits the batch, and `CDRMOutput::commitState` 11% with the atomic commit
  8%), `CRenderPass::render` 19%. Clock reads 3%, DRM property re-reads in aquamarine 4%.
- shm client redrawing a large window (Chromium), 26% CPU: `CGLTexture::update` 71%. About 38% of all samples
  are the kernel allocating, clearing and cache-flushing pages for a new GPU buffer on every upload
  (`shmem_alloc_and_add_folio`, `drm_clflush_sg`), about 23% is the `memcpy`.
- Terminal scrolling fast (foot, shm), 15% CPU: `CGLTexture::update` 74%, the same upload cost as Chromium.
- Workspace switching with three windows and animations, 15% CPU: only 30% is `renderMonitor`. Clock reads are
  17% (`read_hpet` 12%), the rest is spread over animation ticks, layout and damage.
- Hypoland's own code is flat, no function has more than about 1% self time.
- The X200 uses the HPET clocksource (the TSC is marked unstable), so every clock read is a slow syscall.
- Fixed: uploading into a shm texture the GPU still reads from made crocus allocate, clear and cache-flush a
  staging buffer every time (2.4x the cost of the upload, measured with a standalone benchmark). Synchronous
  textures are now double buffered (`CGLTexture::update()`): the update goes into the texture that was shown one
  update ago, plus the damage it missed. Chromium 26.8% -> 12.8% CPU, fast terminal scrolling 14.8% -> 11.3%.
- Fixed: the event loop read the clock once per timer when rescheduling and when timers fire; it reads it once
  per pass now. Workspace switching 14.9% -> 12.7%.
- Checked on 2026-09-27, not worth optimizing:
  - `read_hpet` / `clock_gettime` look big in perf (up to 14% while animating), but that is sampling skid on the
    slow uncached HPET read. A call costs 1.5 us and the compositor makes about 270 per second while animating,
    about 0.04% of a core.
  - The shm upload (`glTexSubImage2D`, crocus copies through a GTT mapping) runs at the memory bus limit:
    1.64 ms for a full 1280x800 frame with glibc memcpy. SSE2 non-temporal stores are the same through the GTT,
    `rep movsb` is slower, and the best case (own WC mapped linear buffer) is 1.45 ms. Hand-written copies or
    inline assembly would not help.
  - `CEGLSync::create` is where Mesa's threaded context runs the whole frame (draws and batch submit). A frame
    with one 60 fps client is only 2 draws and 16 ioctls, all needed except the mode re-read below.
- Open: aquamarine re-reads the CRTC mode (`getCurrentMode()`, 2 ioctls) on every commit, about 2% of the
  compositor's CPU at 60 fps.

Memory (X200, idle Omarchy session 60 s after start, `heaptrack` and `/proc/<pid>/smaps`):
- Fixed: aquamarine created a second EGL context for the primary GPU, which is only needed when a secondary GPU
  blits (`CDRMBackend::primaryRenderer()` now creates it on demand). It cost heap and a Mesa driver thread.
- Fixed: shaders were preprocessed with glslang, only to resolve `#include`. `CShaderLoader` expands includes
  itself now and leaves `#define` / `#if` to the driver, so libglslang (2.5 MiB, private to the compositor) is no
  longer loaded.
- Both together: RSS 113.6 -> 100.1 MiB, anonymous 38.0 -> 27.2 MiB, PSS 73.8 -> 60.1 MiB, one thread less,
  compositor CPU with `weston-simple-egl` unchanged (7.3%).
- What is left: about 17 MiB heap, of which about 7 MiB is Mesa compiler state created with the first shader and
  1.7 MiB the GL context. libLLVM shows 19 MiB RSS but only 6 MiB PSS, the pages are shared with Quickshell and
  Xwayland and come from loading the library (`DRAW_USE_LLVM=0` changes nothing). The Hypoland binary is about
  14 MiB of clean file pages.
- The "started without start-hypoland" notification loads fontconfig and pango (about 1.5 MiB heap) on the X200
  loop, a normal start does not.

Fixed upstream bugs that showed on this hardware:
- `IHyprRenderer::renderText(STextResourceData&&)` queued the text on the hyprgraphics worker and blocked in
  `await()`. On the slow dual core the wakeup gets lost and the compositor hangs forever (seen with
  `debug:overlay`). Text is now rendered synchronously.

Known issues:
- Not a bug: foot 1.28 is never blurred by default. It binds `ext-background-effect-v1` and only sets a blur
  region with `blur=yes` in its `[colors-dark]` section, and `CWindow::shouldBlur()` honours that. Live and
  precomputed blur both work on the X200 for other clients. Do not use foot to judge blur.

## Next steps

Open decisions for the user:
- Pick the icon: the smooth potato in `assets/logo/` or the pixel potato in `assets/logo/retro/` (the README
  banner is the retro one).
- Install the Arch package on the X200 (replaces the system `hyprland`).

Work that is left from the plan above:
- Remove screen shaders.
- Translated strings in `src/i18n/` and the man page still say Hyprland.
- The X200 loop starts `Hypoland` directly, so the "started without start-hypoland" notification shows.

# Code guidelines

Inherited from upstream Hyprland, they apply to Hypoland as well.

## Review guidelines

- Prioritize correctness, lack of regressions, performance, API stability, and code clarity and readability.
- For performance-sensitive paths, flag obvious algorithmic regressions or slow paths.
- For tests, flag missing coverage for changed or new behavior, as long as the testing framework is capable of testing it.
- For config changes (new / removed options) check that the README and this file still describe the defaults.
- Flag silent config breakage: e.g. changing an existing option's behavior. This is not allowed.
- Flag bad config style that breaks this project's style guidelines (further below) and suggest fixes.
- Flag bad code approaches that break this project's core code guidelines (further below) and suggest improvements.

## Style guidelines

- Code must be clang-formatted according to `.clang-format`.
- single-line if and else statements must come without braces. This rule applies only to if / else, not do / while / other.
- Avoid function bodies in headers as much as possible.
- Avoid namespace {} in source files to mark local functions. Prefer `static`.
- Prefer guards in functions and loops: `if (!cond) continue;`
- Prefer forward-declaration in headers to inclusion.
- Leave a stray `,` at the end of brace-enclosed lists to make formatting easier to read.
- Leave a `;` inside empty function bodies for formatting.
- Naming conventions:
 - class: `CMyClass`
 - struct: `SMyStruct`
 - interface: `IMyInterface`
 - class (not struct) member variables: `m_variable`
- Do not use absolute includes from `src/` in headers: instead of `#include "a/b.hpp"` use `#include "../a/b.hpp"` for example. Protocol headers do not require this.

## Core code guidelines

- Stick to good code practices:
 - Avoid complex classes / functions, prefer SRP.
 - Consider using an observer pattern via hyprutils Signals where appropriate.
 - Consider classic OOP patterns where appropriate: Strategy, Singleton, Proxy, etc.
 - Watch out for typical bad practices in code: feature envy, LSP, etc.
 - Use templating and inheritance to clean up code where appropriate.
 - For obtaining singletons, use a `UP<CClass>& myClass();` pattern inside a namespace. This can be implemented in source as making and returning a static ptr.
- Do not, under any circumstance:
 - `using namespace std;`
 - leave uninitialized primitives (int, float, etc)
- Avoid, unless absolutely necessary:
 - the C standard library. Use the C++ STL.
 - `malloc` / `free` / etc
 - C-style pointers. Use SP<> WP<> and UP<> from hyprutils. These are Shared, Weak and Unique pointers respectively. C-style pointers may be used in select scenarios (e.g. destroying fns, where it's impossible to make a mistake) but everywhere else must not be used unless necessary.
 - C-style casts. Use rc<>, sc<>, or cc<> from hyprutils. These are shorthands to equivalent C++ casts.
- Avoid:
 - violating clang-tidy (`.clang-tidy`)
 - manual C-style cleanup: `some_c_thing_new()` and `some_c_thing_free()` can be wrapped.
- Make sure to write tests for code which our Unit (`tests/`) or Integration (`hyprtester/`) tests can test.
