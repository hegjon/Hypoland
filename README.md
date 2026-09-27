<div align="center">
<img src="assets/logo/header.svg" width="760" alt="Hypoland">
</div>

# Hypoland

Hypoland is a fork of [Hyprland](https://github.com/hyprwm/Hyprland), the dynamic tiling Wayland compositor,
for old GPUs that only support **OpenGL ES 2.0 / OpenGL 2.1**.

Hyprland requires OpenGL ES 3.0 and does not start on such hardware. Hypoland targets Intel Gen4 / Gen4.5
graphics (GMA X3100 / 965GM, GMA 4500MHD / GM45) and is developed and tested on a ThinkPad X200.

Hypoland is an independent project. It is not affiliated with or endorsed by Hyprland or its developers.

## Differences from Hyprland

- The renderer runs on OpenGL ES 2.0, with shaders in GLSL ES 1.00.
- [aquamarine](https://github.com/hyprwm/aquamarine) is embedded (`subprojects/aquamarine`) and linked
  statically, with an OpenGL ES 2.0 fallback for its DRM renderer. The system aquamarine is not used.
- The binaries are named `Hypoland` and `start-hypoland`. `Hyprland`, `hyprland` and `start-hyprland`
  are installed as symlinks.
- GPU heavy features (blur, shadows, color management, screen shaders) are being removed.
  Their config options stay registered and are ignored, so existing configs keep loading.

## Compatibility

Hypoland is meant to be a drop-in replacement, everything that talks to Hyprland keeps working:

- Config: `$XDG_CONFIG_HOME/hypr/hyprland.lua`
- IPC: `hyprctl`, the sockets in `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/`, command names,
  JSON output and event names
- `XDG_CURRENT_DESKTOP=Hyprland`
- The Hyprland Wayland protocols

Use the `hyprctl` built from this repository, so the versions match.

Source: <https://github.com/hegjon/Hypoland>

## Building

Dependencies are the same as for Hyprland, except aquamarine. See the
[Hyprland wiki](https://wiki.hypr.land/Getting-Started/Installation/).

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
```

Build for baseline `x86-64` when the target machine is older than the build machine, do not use `-march=native`.

## Credits

All credit for the compositor goes to [Hyprland](https://github.com/hyprwm/Hyprland) and its contributors.
Hyprland thanks wlroots, tinywl, Sway, Vivarium, dwl and Wayfire.

## License

BSD 3-Clause, the same as Hyprland. See [LICENSE](LICENSE).
