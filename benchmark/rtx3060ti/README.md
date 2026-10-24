# RTX 3060 Ti before and after benchmark

This harness calls the official CUDA 12.6 runtime and cuBLAS DLLs directly
through Python `ctypes`. It does not require PyTorch, the CUDA toolkit, a C++
compiler, or administrator rights. The setup pins NVIDIA redistributable ZIPs
to SHA-256 values from NVIDIA's CUDA 12.6 manifest. It does not change GPU
clocks, power limit, firmware, or driver settings.

On this PC, PyTorch's `c10.dll` was blocked by Windows Application Control, so
the direct cuBLAS harness is used for both phases. Install the pinned DLLs once:

```powershell
# Run from the repository root.
.\benchmark\rtx3060ti\setup.ps1
```

For each phase, the same unchanged `measure.py` measures 4096 x 4096 GEMM,
with a two-second warmup and 30 CUDA-event samples for each mode in each of
three trials. Modes are FP32 pedantic, TF32 tensor input with FP32
accumulation/output, FP16 tensor input with FP32 accumulation/output, and BF16
tensor input with FP32 accumulation/output. The benchmark checks two result
elements against the expected value. TF32 uses `CUBLAS_COMPUTE_32F_FAST_TF32`,
which permits cuBLAS to use tensor cores; the harness does not inspect the
selected kernel. Close other GPU-heavy applications for a cleaner comparison.

The locked-state baseline was taken with this command:

```powershell
python .\benchmark\rtx3060ti\measure.py --phase before
```

After returning to Windows with the unlock confirmed, run:

```powershell
# Run from the repository root.
python .\benchmark\rtx3060ti\measure.py --phase after
$after = Get-ChildItem .\benchmark\results\rtx3060ti -Directory |
  Where-Object Name -Like '*-after-*' |
  Sort-Object Name -Descending |
  Select-Object -First 1
python .\benchmark\rtx3060ti\compare.py `
  .\benchmark\rtx3060ti\baseline\20261024T164051Z-before-19d2e439\summary.json `
  (Join-Path $after.FullName 'summary.json')
```

The baseline also remains under
`benchmark/results/rtx3060ti/20261024T164051Z-before-19d2e439`.
Each measurement creates a new timestamped directory and writes with exclusive
file creation. The tracked `baseline` copy preserves the original result,
environment, and all per-trial samples. Its `script_sha256` pins the exact
benchmark source used. The comparator refuses a different script, Python
version, CUDA/cuBLAS DLL hashes or versions, GPU identity, or workload settings.
It displays the driver version, power limit, idle power draw, clock,
temperature, VRAM use, and utilization for both phases and flags changed driver
or power limits. The reported ratios are synthetic GEMM throughput only; they
are not game frame rates or proof of a hardware configuration change.
