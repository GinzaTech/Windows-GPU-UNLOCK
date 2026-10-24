"""Compare immutable before and after summaries from measure.py."""

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args()
    before = json.loads(args.before.read_text(encoding="utf-8"))
    after = json.loads(args.after.read_text(encoding="utf-8"))
    if (before["phase"], after["phase"]) != ("before", "after"):
        raise SystemExit("Expected a before summary followed by an after summary")
    checks = (
        "script_sha256", "python", "dll_sha256", "versions",
        "gpu_name", "gpu_pci_id", "gpu_subsystem_id", "gpu_bus_id",
        "matrix_n", "warmup_seconds", "samples_per_mode", "trials",
    )
    for key in checks:
        if before["environment"][key] != after["environment"][key]:
            raise SystemExit(f"Benchmark environment differs: {key}")
    before_idle = before["environment"]["idle_samples"][-1]
    after_idle = after["environment"]["idle_samples"][-1]
    print("GPU context (before -> after):")
    for key in (
        "driver_version", "power.limit", "power.draw",
        "clocks.current.sm", "temperature.gpu", "memory.used",
        "utilization.gpu",
    ):
        old, new = before_idle[key], after_idle[key]
        flag = " CHANGED" if key in ("driver_version", "power.limit") and old != new else ""
        print(f"  {key}: {old} -> {new}{flag}")
    baseline = {row["name"]: row for row in before["results"]}
    measured = {row["name"]: row for row in after["results"]}
    if baseline.keys() != measured.keys():
        raise SystemExit("Benchmark modes differ")
    print("mode, before_TFLOPS, after_TFLOPS, ratio")
    for name in baseline:
        old = baseline[name]["median_tflops"]
        new = measured[name]["median_tflops"]
        print(f"{name}, {old:.2f}, {new:.2f}, {new / old:.3f}x")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
