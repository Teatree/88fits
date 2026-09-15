---
name: gdunit
description: Write and run gdUnit4 tests for the 88fits Godot project headlessly, including a single test file. Use when adding logic to core/ or when a bug needs a regression test.
---

# gdUnit4 in 88fits

gdUnit4 v6.2.1 is vendored at `game/addons/gdUnit4`. Tests live in `game/tests/` and end in `_test.gd`.

## Run

```
GODOT="D:/_projects/88fits/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64.exe"
# all tests
"$GODOT" --headless --path D:/_projects/88fits/game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
# one file
"$GODOT" --headless --path D:/_projects/88fits/game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/stat_sheet_test.gd
```

Exit code 0 means all passed. The report is printed to stdout and written to `game/reports/`.

If gdUnit4 ever fails to load (plugin/version mismatch), fall back to the dependency-free runner:
```
"$GODOT" --headless --path D:/_projects/88fits/game --script res://tools/run_tests.gd
```
which runs every `test_*` method in `tests/*_test.gd` and prints PASS/FAIL.

## Writing a test

```gdscript
extends GdUnitTestSuite

func test_stat_sheet_multiplies() -> void:
    var s := StatSheet.new()
    s.set_base("might", 1.0)
    s.add_effect(Effect.make("might", "mul", 0.2))
    assert_float(s.get_stat("might")).is_equal_approx(1.2, 0.001)
```

Rules: one behaviour per test, no scene tree unless needed (`auto_free(node)` when it is), test the data path (Registry, StatSheet, CardPool, WaveDirector maths, TextGen) rather than rendering.
