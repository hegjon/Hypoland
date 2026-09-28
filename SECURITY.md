# Security Policy

If you have found a bug that affects the security of your system, please report it privately instead of
opening a public issue.

## Supported versions

Only the most recent release and `master` are supported.

## What is not a security issue

- An app can execute a command when run outside of a sandbox
- An app can write / read the compositor's sockets when run outside of a sandbox
- Crashes
- Things that are protected via permissions when the permission system is disabled

## What is a security issue

- A sandboxed application executing arbitrary code via Hypoland
- An application being able to modify Hypoland's code on the fly
- An application being able to keylog / track the user's activity beyond what the Wayland protocols allow

## How to report security issues

Use [Report a vulnerability](https://github.com/hegjon/Hypoland/security/advisories/new) on GitHub.

Most of Hypoland's code comes from [Hyprland](https://github.com/hyprwm/Hyprland). If the issue is in code
that Hypoland shares with Hyprland, it probably affects Hyprland too: please also report it to Hyprland,
following [their security policy](https://github.com/hyprwm/Hyprland/security/policy).
