# Run the RTX 3060 Ti compute benchmark yourself

Double-click [Run-Benchmark.cmd](Run-Benchmark.cmd) on Windows. Menu **1** displays the archived TFLOPS figures without loading the GPU. When both original summaries are present, it runs the comparator; a public checkout without the private `after` capture shows only the published report table. Choose **2** or **3** to measure the current Windows session as `before` or `after`. The launcher displays FP32, TF32, FP16 and BF16 TFLOPS and saves `environment.json`, three `trial-*.json` files and `summary.json` under `benchmark/results/rtx3060ti/`. Menu **4** compares two summaries, **5** reopens one summary, **6** opens the results folder and **7** shows current power, temperature, clocks and utilization.

A new measurement needs 64-bit Python 3.12 on `PATH`, the NVIDIA driver, and CUDA/cuBLAS DLLs. If the DLLs are absent, the launcher asks before downloading SHA-256-pinned official packages. The existing [measure.py](measure.py) pins this test PC's GPU, subsystem and bus IDs. Another RTX 3060 Ti will be rejected rather than silently compared against this PC's baseline.

## Make a new before/after pair

1. Restore default GPU clocks, disable automatic tuning and overclocking, and keep the driver and power limit the same across runs (the test PC used 200 W). After previous tuning experiments, restart Windows and **verify** that offsets stayed at default; tuning software may reapply them. Close games, video and other GPU work.
2. Boot normally through **Windows Boot Manager**, open the launcher and choose **2**. Save the printed path to the `before` `summary.json`.
3. Shut down fully. On the test ASUS PC, choose **F8 → GPU Headless UNLOCK - EXPERIMENTAL** at startup. Treat the session as unlocked only if a **fresh log from that boot** reports `transaction result=0`, `FLR=1` and `clean=1`, and Windows detects the GPU again. See the [installation and verification guide](../../docs/WINDOWS-RTX3060TI.en.md).
4. Open the launcher and choose **3**. Save the `after` summary path. Choose **4** and paste the two exact paths to display TFLOPS and ratios.

The `before` and `after` values are labels, not proof of a UEFI unlock. Keep the same [measure.py](measure.py), CUDA/cuBLAS DLLs, driver, power limit, clocks and background load. [compare.py](compare.py) rejects different benchmark code, Python versions, DLLs, GPU identity or workload and displays driver/power changes for review. Do not use `benchmark/run-benchmark.ps1` for this card: that script targets an RTX 3090.

The workload is cuBLAS 4096 × 4096 matrix multiplication: two seconds of warmup, 30 CUDA event samples per mode and three trials. It reports median synthetic compute TFLOPS, **not game FPS**. Only the first and last output elements are checked. See the [recorded result and evidence limits](../../docs/WINDOWS-RTX3060TI-RESULTS.en.md).
