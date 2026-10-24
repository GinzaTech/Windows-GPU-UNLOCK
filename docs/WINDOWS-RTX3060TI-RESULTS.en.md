# RTX 3060 Ti Windows hardware and performance report

[Tiếng Việt](WINDOWS-RTX3060TI-RESULTS.vi.md) · [Installation guide](WINDOWS-RTX3060TI.en.md)

## Scope and method

On 2026-10-25 (Asia/Bangkok), one ASUS TUF GAMING Z690-PLUS WIFI D4, BIOS 2602, Core i7-14700K, Windows 11 Pro, and RTX 3060 Ti `10DE:2489 / 1043:8827` with VBIOS `94.04.6B.00.11` ran the F8-selected headless UEFI entry. Both benchmarks used NVIDIA driver 617.42 and the unchanged **200 W** power limit. This establishes **one machine and one unlock run**, not compatibility with every 3060 Ti.

The same `benchmark/rtx3060ti/measure.py` (SHA-256 `557CDFF46B3F83F5E1BEB1EB55EB1E7479B71EDDB397BA7B0BAF323BDA174C6B`) called CUDA 12.6 and cuBLAS 12.6 for 4096 × 4096 GEMM. Each mode used a two-second warmup, 30 CUDA event samples, and three trials; the table shows medians. The comparator matched Python 3.12.8, DLL hashes, GPU identity, and workload settings across the before and after runs.

| GEMM mode | Before (TFLOPS) | Read-only diagnostic (TFLOPS) | After unlock (TFLOPS) | After / Before |
| --- | ---: | ---: | ---: | ---: |
| FP32 pedantic | 10.23 | 11.20 | 10.66 | 1.042× |
| TF32 Tensor, FP32 accumulation | 16.70 | 17.99 | 34.62 | **2.072×** |
| FP16 Tensor, FP32 accumulation | 35.21 | 35.35 | 66.91 | **1.900×** |
| BF16 Tensor, FP32 accumulation | 35.12 | 35.36 | 67.13 | **1.912×** |

The three after-trial medians ranged from 10.55–10.90 FP32, 34.58–34.84 TF32, 66.48–67.21 FP16, and 66.73–67.25 BF16 TFLOPS. The separate read-only diagnostic remained near the old Tensor throughput, supporting the conclusion that the large increase followed the unlock transaction. Its FP32 result exceeded the after result, so there is **no evidence of a stable FP32 gain**.

## UEFI and Windows evidence

Wrapper log `HLS000005.TXT` records cold SS0 `0x54372012` and SS1 `0x4`, successful preflight, detachment of three EDID children and NVIDIA GOP, and readiness to launch the child. Child `AUTO000000/REPORT.TXT` records SS0/SS1 `0x88888888/0x8` both before **and** after PCIe FLR, `transaction result=0`, `started=1`, `quiesced=1`, `fault=0`, `retained=0`, `maps=0`, `FLR=1`, and `FINAL status=0 ... clean=1`. The wrapper then started Windows; `nvidia-smi` found the card and the after benchmark completed. At the end of that benchmark the GPU reported 99% utilization, about 192 W, and 60 °C. Windows Boot Manager was restored to first priority; the unlock entry remains F8-only.

Local evidence references:

- Source-controlled baseline: [`benchmark/rtx3060ti/baseline/20261024T164051Z-before-19d2e439/summary.json`](../benchmark/rtx3060ti/baseline/20261024T164051Z-before-19d2e439/summary.json).
- After summary: `benchmark/results/rtx3060ti/20261024T183204Z-after-84d1f28f/summary.json`, SHA-256 `CE366261222471E930FA6AF6E6508989172EF111B2CF7E6B154BBD3CC2B40FF6`.
- Child log: `research/results/rtx3060ti-headless/20261024T183145Z-1f74077a/AUTO000000/REPORT.TXT`, SHA-256 `2017C986CC1F394290FC64440398CA8C9BCF0F1EE1C4B063E99CE1DE4D3C2838`.
- Wrapper log: `research/results/rtx3060ti-headless/20261024T183145Z-1f74077a/HLS000005.TXT`, SHA-256 `3454C2458B02DFE1C8AF79922C43A7A4CF770109CA79151D131B255190E40F59`.

UEFI logs and the after result are **private machine captures**, excluded from the public release. The hashes and filtered table permit comparison with the local originals without publishing the entire capture. GEMM throughput does not establish game FPS, whole-application speedup, sleep/resume behavior, repeated automatic startup, or long-term stability. No game was measured on this PC.
