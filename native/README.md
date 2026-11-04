# The crowd's compiled loops (pass 125)

`src/` is a small C++ library (GDExtension, class `CrowdCore`) that runs the crowd's hottest loops. `game/core/systems/EnemyManager.gd`
stays the only owner of the rules and the data; the library reads and writes its packed arrays in place.

**What runs here:** the two grids, who is drawn, a walking creature's whole tick (chase and flock brains, plain state), every other
creature's push, a dying body's tick and most of the draw. **What stays in the script:** every other brain, every status with
side effects, damage, attacks, bosses. The library hands those back one creature at a time, in index order.

**The rule that keeps replays and the fallback working:** a run plays exactly the same with the library or without it. The sums in
`crowd_core.cpp` follow the script's, with its number types: a GDScript float is a double, a `Vector3` component and a
`PackedFloat32Array` element a float. If you change a rule in the plain walker's path, change it in both places.

## Files

- `src/crowd_core.cpp`: the tick (`bind`, `rebuild_grid`, `refresh_drawn`, `advance`, `sep_push`).
- `src/crowd_render.cpp`: the draw (`render`, `put_instance`, `put_shadow`, `render_finish`).
- `SConstruct`: the build. On Android `-ffp-contract=off` matters: without it clang fuses `a * b + c`, and the phone's sums
  stop matching the PC's.
- `../game/bin/`: the built libraries and `crowd.gdextension`. They are committed, so building the game needs no compiler.

## Building

```
python tools/build_native.py            # both libraries (--windows, --android for one)
python tools/build_native.py --setup    # fetches SCons, godot-cpp and the Android NDK into tools/dl/native/ (git-ignored)
```

Windows needs Visual Studio or its Build Tools. Close the Godot editor first: while it has the project open it holds the DLL and
the link fails.

## Proving a change

```
# the same run, script against library: every checkpoint must be equal
bash tools/godot.sh --headless --fixed-fps 60 --path game --script res://tools/_p125_NATIVE_proof.gd -- mode=record native=0 out=<f> hero=drifter stage=1 seed=7 limit=300 check=1
bash tools/godot.sh --headless --fixed-fps 64 --path game --script res://tools/_p125_NATIVE_proof.gd -- mode=replay native=1 file=<f> out=<report.json>
# the same pictures: no pixel more than 1/255 apart
bash tools/godot.sh --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --path game --script res://tools/_p125_NATIVE_pixels.gd -- out=<dir>
# what a crowd of N costs, either way
bash tools/godot.sh --audio-driver Dummy --resolution 504x1122 --fixed-fps 60 --disable-vsync --path game --script res://tools/_p125_CROWD_bench.gd -- n=800 [native=0]
```

`native=0` on any tool's command line turns the library off for that run; the developer menu has the same switch for the phone.
