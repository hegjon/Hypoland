# Overnight job: lower RAM and CPU usage

Brief for an unattended run. The user is asleep: nobody can answer questions, type the disk password or
look at the screen. Read `AGENTS.md` first, its rules apply.

## Goal

Find changes that lower the compositor's memory or CPU time on the X200 and prove each one with a measurement.
A change without a measured gain outside the noise is not kept.

## Scope (decided by the user on 2026-09-27)

Allowed:
- Internal optimizations without a visible change in behaviour.
- Patches to the embedded aquamarine in `subprojects/aquamarine`.

Not allowed, write them down as proposals in the journal instead:
- Removing features, also the ones `AGENTS.md` lists for removal (screen shaders and so on).
- Changing defaults of config options.
- Anything that touches the compatibility requirements in `AGENTS.md`.
- Changes to the X200 outside `~/hypoland` and `/tmp` (no packages, no system config). The benchmark sets the
  CPU governor and the Omarchy idle flags for its run and puts them back.

## Rules

- Never reboot the X200. Restart the compositor with `pkill -x hypoland`, a dead loop with
  `ssh root@x200 systemctl restart getty@tty1`. If the X200 stays unreachable or the GPU hangs for good, stop
  the job and write down what happened.
- Work on the local branch `overnight/ram-cpu`. One commit per kept change, with the measured numbers in the
  commit message. Never push. Leave `master` and the uncommitted files `README.md` and `example/hyprland.lua`
  as they are (they travel with the working tree, do not add them to a commit).
- One change per experiment, so every number belongs to one cause.
- Revert an experiment that does not pass or does not gain (`git checkout -- <files>`), keep a line about it in
  the journal so it is not tried twice.
- Build for `x86-64`, never `-march=native`.
- Leave the X200 as it was found: the normal build of the last kept commit installed, no `~/hypoland/env`, no
  `~/hypoland/test.lua`, `./test-x200.sh` passing.

## How to measure

`./bench.sh <label>` builds, deploys, restarts, runs `./test-x200.sh` (has to pass) and measures on the
normal build: memory 60 s after the start and again after the workloads, CPU time of five workloads
(idle, GPU client at 60 fps, terminal scrolling, Chromium over shm, workspace switching), three rounds of 20 s
each. It takes about 10 minutes. Results go to `test-results/bench-<time>-<label>/values.txt`.

`./bench.sh --compare <baseline dir> <candidate dir>` prints the difference and marks what is outside the
spread of the rounds.

- The baseline of `master` was measured twice, see `test-results/bench-*-baseline-a` and `-b`. The difference
  between those two is the noise between two starts of the same build: up to 0.2 points of CPU time and
  1.2 MiB of memory (`AnonHugePages` jumps by whole 2 MiB pages, 8 MiB between the two runs). `--compare` only
  marks differences above 0.3 points and 1.5 MiB. A gain has to be clearly larger.
- Measure a candidate that looks good a second time before it is kept.
- After every kept change the new measurement is the baseline for the next one.
- The benchmark runs with the `performance` governor, so its CPU numbers are lower than the ones in `AGENTS.md`
  (measured with `schedutil`). Compare benchmark numbers only with benchmark numbers.
- `fps.gpu-client` has to stay at about 60. Less CPU time with fewer frames is not a gain.
- A run with an `invalid.*` line (screensaver, lock, compositor restart or crash) does not count.
- For finding where the time or the memory goes: `./profile.sh` (perf, separate build with frame pointers),
  `heaptrack` and `/proc/<pid>/smaps` on the X200. Wrap remote commands in `timeout`.
- A change to rendering is only verified on the X200: no `Failed to link shader` in `~/hypoland/loop.log`, the
  screenshot of `test-x200.sh` shows the window. Look at the screenshot.

## Journal

Keep `test-results/overnight/journal.md` up to date after every experiment, so the run can be continued after
an interruption and read in the morning:

| # | change | result dir | RAM (Pss, Anonymous) | CPU per workload | kept / reverted, why |

End with a summary: what was kept (commit ids), total gain against `baseline-a`, proposals that were out of
scope, and open problems.

## Candidates

Starting points, ordered by expected gain. Measure first, the list is a guess. Add what profiling shows.

Memory (start of the night: Rss 103 MiB, Pss 62 MiB, anonymous 29 MiB, heap 18 MiB, 10 threads):
1. Transparent huge pages. The X200 runs with THP `always` and 16 to 18 MiB of the 29 MiB anonymous memory are
   huge pages, so partly used 2 MiB blocks count in full. Try `madvise(MADV_NOHUGEPAGE)` style solutions or the
   glibc tunables. `prctl(PR_SET_THP_DISABLE)` is inherited by every client the compositor starts, so it would
   have to be reset in the child before `exec`.
2. Mesa's shader compiler state, about 7 MiB after the first shader. `glReleaseShaderCompiler()` is GLES2 API.
   Check whether crocus gives anything back, and what a later compile (config reload) costs.
3. Shaders that are compiled at start but never used with the default options. Compile them on first use.
4. glibc malloc: number of arenas (`M_ARENA_MAX`) with 10 threads, `malloc_trim` after the start,
   the existing `mallopt(M_TRIM_THRESHOLD)` in `src/Compositor.cpp`.
5. What the 10 threads are and whether each is needed (stack and arena per thread).
6. The binary: 18 MiB, about 14 MiB of clean pages in memory. `-ffunction-sections -Wl,--gc-sections`, LTO,
   `-Wl,-z,relro` effects on private dirty pages, large static tables (config descriptions, i18n).
7. Heap users at idle according to `heaptrack`: Lua state, config values, textures kept in system memory,
   fontconfig / pango from the "started without start-hypoland" notification.

CPU:
1. aquamarine reads the CRTC mode on every commit (`getCurrentMode()`, 2 ioctls, about 2% of the compositor at
   60 fps) and re-reads DRM properties (about 4%). Cache them, invalidate on modeset and hotplug.
2. `CEGLSync::create` on every frame: check whether the fence is used at all on this hardware (no explicit
   sync on Gen4) and what the frame costs without it. It is also where Mesa flushes, so the gain may be small.
3. Workspace switching: only 30% of the time is rendering. Animation ticks, layout recalculation and damage.
4. Wakeups at idle: timers and event sources that fire without work (`perf stat`, `strace -c` for 30 s).
5. Compiler flags: `-O2` against `-O3`, LTO, measured and not assumed.
6. Per-frame work that does not depend on the damage: passes over all windows, string handling, allocations in
   the render path (`perf` with `--call-graph`, `heaptrack` allocation counts while a client runs).

Checked before and not worth repeating (details in `AGENTS.md`): clock reads (`read_hpet`), the speed of the
shm upload copy, blur.
