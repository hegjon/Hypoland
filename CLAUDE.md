# Hypoland

Hypoland is a fork of Hyprland that targets old GPUs limited to **OpenGL ES 2.0 / OpenGL 2.1**
(Intel Gen4/Gen4.5: GMA X3100 / 965GM, GMA 4500MHD / GM45). Upstream Hyprland requires GLES 3.x,
so its renderer and shaders must be ported down to GLSL ES 1.00.

## Hardware

- **Dev machine:** this desktop. All editing and compiling happens here.
- **Test machine:** ThinkPad X200 on the same LAN (GM45 / GMA 4500MHD, Core 2 Duo, Mesa `crocus` driver,
  i915 kernel driver). Currently runs Omarchy; stock Hyprland fails to start on it (expected: no GLES 3).
- X200 access: `ssh x200` (ssh config alias -> 192.168.95.91, user `a`, uid 1000, key auth works).
  6 GB RAM, 2 cores, Arch kernel 7.1.x, Mesa 26.2, stock `hyprland` 0.56.2 installed, 100 GB free in `/home`.
- Root on the X200: `ssh root@x200` (key auth). Test tools are installed: `waybar`, `weston-simple-egl`,
  `glmark2-es2-wayland`, `pidstat`, `eglinfo`, `grim`, `foot`.

## Repository

- Repo lives in `/home/jonny/Work/hypoland`, branch `hypoland`.
- Remotes: `upstream` = hyprwm/Hyprland, `hegjon` = the user's fork (github.com/hegjon/Hyprland).
- Base: `hegjon/gles2-legacy-renderer` (one commit on upstream main, v0.56.0+141). It already adds a working
  GLES2 path chosen at **runtime** (`CHyprOpenGLImpl::m_legacyGLES`, `GLES2ShaderCompat` translating
  GLSL ES 3.00 -> 1.00), verified on the X200. Hypoland builds on this rather than re-porting the renderer.
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
  - The embedded aquamarine is patched in-tree the same way (GLES2 context and ES 1.00 shaders only).
  - Framebuffers have one color attachment and no stencil. FP16 is always unsupported.
- The config is Lua in this Hyprland version (`~/.config/hypr/hyprland.lua`, Omarchy uses it). With a Lua config
  `hyprctl keyword` answers `unknown request`; use `hyprctl eval "hl.config({...})"`.
- Both machines have identical hypr* library versions (aquamarine 0.15.1, hyprutils 0.14.2, hyprlang 0.6.8,
  hyprcursor 0.1.13, hyprgraphics 0.5.1), so a desktop build links cleanly on the X200. Keep them in sync.
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
- Config path: `$XDG_CONFIG_HOME/hypr/hyprland.conf` (fallback `~/.config/hypr/hyprland.conf`), and `--config`.
- IPC sockets: `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock` and `.socket2.sock`.
- The `HYPRLAND_INSTANCE_SIGNATURE` env var, IPC command names, JSON output format, and event names.
- `XDG_CURRENT_DESKTOP=Hyprland` (needed by xdg-desktop-portal-hyprland and app detection).
- Hyprland Wayland protocols used by Quickshell (Omarchy's shell): focus grab, global shortcuts, toplevel export.

Removed features must stay **registered as no-op config options** (warn once, never error), so existing
configs such as Omarchy's load without the red error bar. `hyprctl keyword <removed option> ...` must return `ok`.

Ship `hyprctl` built from this fork so versions match. The Arch package should declare
`provides=('hyprland')` and `conflicts=('hyprland')`.

## Features to remove or default off

Remove/rewrite (GPU heavy): color management / HDR pipeline,
screen shaders, shadows, per-window offscreen rendering where avoidable.

Keep: blur (dual Kawase and the GLES2-capable variants), default off. Decided by the user on 2026-09-27 after
measuring it on the X200: about 1% extra compositor CPU and 57-60 fps. Do not remove it.

Optional, default off: animations (keep short slides only, no fades), animated/gradient borders,
rounded corners (radius 0 must skip the shader path), dim inactive, inactive opacity, fractional scaling.

CPU/RAM: drop the plugin system and hyprpm; default to XCursor over hyprcursor SVG; keep Xwayland optional.

Keep (they help): damage tracking, direct scanout, hardware cursor planes.

Prefer compile-time flags (e.g. `-DNO_BLUR`, `-DNO_ANIMATIONS`) so removed code isn't built.

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
   - logs: `$XDG_RUNTIME_DIR/hypr/*/hyprland.log` and `~/.local/share/hyprland/`
4. Wrap steps 1-3 in one script, `./test-x200.sh`, that prints a short pass/fail summary and the log tail.
   Prefer running this script over improvising SSH commands.
5. Fast local checks: run nested on the desktop with `LIBGL_ALWAYS_SOFTWARE=1 MESA_GLES_VERSION_OVERRIDE=2.0`.
   This is NOT a faithful GM45 test (llvmpipe allows extra features); the X200 is the final judge.
6. Test the compositor with Waybar first; bring Quickshell back once the renderer is stable
   (disable window previews and QML effects on the X200; compare `QT_QUICK_BACKEND=software`).

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

## Status (2026-09-27)

The first milestone is reached: the GLES2-only build runs the full Omarchy session on the X200 (Quickshell bar,
wallpaper, notifications, windows, Xwayland, Chromium). `./test-x200.sh` passes, including a check that the
window is really drawn (screenshot before/after).

Measured on the X200 (1280x800, Omarchy config):
- idle compositor CPU 0%, RSS 115-130 MiB (about 80 MiB of it is Mesa/LLVM file mappings)
- `weston-simple-egl` 60 fps, compositor 8-9% CPU; blur on costs about 1% more
- 4 windows with rounding, shadows, blur, opacity, dim and animations: 58-60 fps, compositor 12% CPU
- `glmark2-es2-wayland` score 127; glxgears through Xwayland 30 fps
- Chromium falls back to software rendering (it wants GLES3 itself); compositor 25% CPU uploading its shm frames

Findings worth keeping:
- `quirks:skip_non_kms_dmabuf_formats` must default to false. Gen4 primary planes have no alpha formats, so with
  the upstream default no client gets an EGL config with alpha and Quickshell's fullscreen overlay turns black.
- Omarchy 4 locks with its Quickshell shell, `hyprlock` / `hypridle` are not installed.
- Defaults changed: blur, shadows, animations and hyprcursor off; logo background and splash are gone
  (`misc:disable_hyprland_logo` is a no-op); hyprpm is only built with `-DWITH_HYPRPM=ON`.
- Packaging: `packaging/arch/PKGBUILD` builds from the working tree (`makepkg -f`).

Tools:
- `HYPOLAND_PROFILE_PASS=1` times every render pass element on the GPU (glFinish) and prints per-type totals to
  stderr every 120 frames. On the X200 put it in `~/hypoland/env` (sourced by the loop), read `~/hypoland/loop.log`.
  It slows rendering down, remove the env file afterwards.
- `debug:overlay` works and shows frame and render times.

Performance findings (X200, profiler):
- Fill rate is the limit: one fullscreen 1280x800 blended surface costs about 3.3 ms, a clear 1.4 ms, the copy
  from the work buffer to the output 3.4 ms. A full redraw of 4 windows plus the Quickshell layers is 14-17 ms,
  so full-screen changes run at 30 fps. Damage-tracked updates cost 2-4 ms and hold 60 fps.
- Borders cost about 0.4 ms per window on a full redraw, they are already limited to the border ring.
- Omarchy gives every window an opacity rule (`default-opacity` tag), so no window occludes the wallpaper.
  With opaque windows the occlusion pass skips what is underneath.
- Quickshell's notification overlay is a transparent fullscreen layer that is blended over every damaged area.
- Not done: rendering straight to the output buffer would save the copy (about 25% of a frame), but it changes
  how damage and buffer age work.

Fixed upstream bugs that showed on this hardware:
- `IHyprRenderer::renderText(STextResourceData&&)` queued the text on the hyprgraphics worker and blocked in
  `await()`. On the slow dual core the wakeup gets lost and the compositor hangs forever (seen with
  `debug:overlay`). Text is now rendered synchronously.

Known issues:
- Not a bug: foot 1.28 is never blurred by default. It binds `ext-background-effect-v1` and only sets a blur
  region with `blur=yes` in its `[colors-dark]` section, and `CWindow::shouldBlur()` honours that. Live and
  precomputed blur both work on the X200 for other clients. Do not use foot to judge blur.
- The C++ color management pipeline and the mirror texture plumbing are still compiled, but never enabled.

## First milestone

Hypoland starts on the X200 with a bare GLES 2 renderer: windows visible, input works, `hyprctl` responds,
the Omarchy config loads without errors. Add features back one at a time.

## First tasks for the agent

1. Ask the user for the missing details in the Hardware TODO.
2. Set up SSH key access to the X200 and the tty1 autologin loop.
3. Write `test-x200.sh`.
4. Confirm the failure: run stock Hyprland on the X200 and capture the EGL/GLES error from the log.
5. Start the fork: rename binary/branding only, then begin porting the renderer to GLES 2.
