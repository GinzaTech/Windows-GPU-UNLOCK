"""Pinned CUDA 12.6/cuBLAS GEMM baseline for this PC's RTX 3060 Ti.

Uses official NVIDIA redistributable DLLs through Python ctypes. It does not
alter GPU settings or depend on unsigned PyTorch DLLs blocked on this PC.
"""

from __future__ import annotations

import argparse
import ctypes as C
import hashlib
import json
import statistics
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4


N = 4096
WARMUP_SECONDS = 2.0
SAMPLES = 30
TRIALS = 3
GPU_NAME = "NVIDIA GeForce RTX 3060 Ti"
GPU_ID = "0x248910DE"
SUBSYSTEM_ID = "0x88271043"
BUS_ID = "00000000:01:00.0"
MODES = (
    ("fp32_pedantic", 0, 0x3F800000, 2, 68),
    ("tf32_tensor_fp32_accumulate", 0, 0x3F800000, 3, 77),
    ("fp16_tensor_fp32_accumulate", 2, 0x3C00, 1, 68),
    ("bf16_tensor_fp32_accumulate", 14, 0x3F80, 1, 68),
)
SMI_FIELDS = (
    "name", "pci.bus_id", "pci.device_id", "pci.sub_device_id",
    "driver_version", "compute_cap", "power.limit", "power.draw",
    "clocks.current.sm", "temperature.gpu", "memory.used", "utilization.gpu",
)
ROOT = Path(__file__).resolve().parents[1]
PACKAGE_ROOT = ROOT / "packages" / "rtx3060ti"
CUDART_PATH = (
    PACKAGE_ROOT / "cuda_cudart"
    / "cuda_cudart-windows-x86_64-12.6.37-archive" / "bin" / "cudart64_12.dll"
)
BLAS_DIR = (
    PACKAGE_ROOT / "libcublas"
    / "libcublas-windows-x86_64-12.6.0.22-archive" / "bin"
)
BLAS_PATH = BLAS_DIR / "cublas64_12.dll"
BLAS_LT_PATH = BLAS_DIR / "cublasLt64_12.dll"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def gpu_state() -> dict[str, str]:
    command = [
        "nvidia-smi", "--query-gpu=" + ",".join(SMI_FIELDS),
        "--format=csv,noheader,nounits",
    ]
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        raise RuntimeError(f"Expected one NVIDIA GPU, found {len(lines)}")
    values = [part.strip() for part in lines[0].split(",")]
    if len(values) != len(SMI_FIELDS):
        raise RuntimeError("Unexpected nvidia-smi CSV fields")
    state = dict(zip(SMI_FIELDS, values, strict=True))
    if (
        state["name"] != GPU_NAME
        or state["pci.bus_id"] != BUS_ID
        or state["pci.device_id"].casefold() != GPU_ID.casefold()
        or state["pci.sub_device_id"].casefold() != SUBSYSTEM_ID.casefold()
        or state["compute_cap"] != "8.6"
    ):
        raise RuntimeError("GPU identity changed; refusing comparison run")
    return state


def check_idle() -> list[dict[str, str]]:
    states = []
    for index in range(5):
        states.append(gpu_state())
        if index != 4:
            time.sleep(0.2)
    median_util = statistics.median(int(x["utilization.gpu"]) for x in states)
    if median_util > 15:
        raise RuntimeError(f"GPU is busy: median utilization {median_util}%")
    if int(states[-1]["memory.used"]) > 2048:
        raise RuntimeError("GPU memory use exceeds 2048 MiB before benchmark")
    if int(states[-1]["temperature.gpu"]) > 65:
        raise RuntimeError("GPU temperature exceeds 65 C before benchmark")
    return states


class CudaBlas:
    def __init__(self) -> None:
        for path in (CUDART_PATH, BLAS_PATH, BLAS_LT_PATH):
            if not path.is_file():
                raise FileNotFoundError(f"Run setup.ps1 first: {path}")
        self._dll_dirs = [
            __import__("os").add_dll_directory(str(CUDART_PATH.parent)),
            __import__("os").add_dll_directory(str(BLAS_DIR)),
        ]
        self.cuda = C.WinDLL(str(CUDART_PATH))
        self.blas = C.WinDLL(str(BLAS_PATH))
        ptr = C.c_void_p
        cint = C.c_int
        size = C.c_size_t
        self._cuda_count = self._bind(self.cuda, "cudaGetDeviceCount", [C.POINTER(cint)])
        self._cuda_set = self._bind(self.cuda, "cudaSetDevice", [cint])
        self._cuda_malloc = self._bind(self.cuda, "cudaMalloc", [C.POINTER(ptr), size])
        self._cuda_free = self._bind(self.cuda, "cudaFree", [ptr])
        self._cuda_memcpy = self._bind(self.cuda, "cudaMemcpy", [ptr, ptr, size, cint])
        self._cuda_sync = self._bind(self.cuda, "cudaDeviceSynchronize", [])
        self._event_create = self._bind(self.cuda, "cudaEventCreate", [C.POINTER(ptr)])
        self._event_record = self._bind(self.cuda, "cudaEventRecord", [ptr, ptr])
        self._event_sync = self._bind(self.cuda, "cudaEventSynchronize", [ptr])
        self._event_elapsed = self._bind(
            self.cuda, "cudaEventElapsedTime", [C.POINTER(C.c_float), ptr, ptr]
        )
        self._event_destroy = self._bind(self.cuda, "cudaEventDestroy", [ptr])
        self._runtime_version = self._bind(
            self.cuda, "cudaRuntimeGetVersion", [C.POINTER(cint)]
        )
        self._driver_version = self._bind(
            self.cuda, "cudaDriverGetVersion", [C.POINTER(cint)]
        )
        self._blas_create = self._bind(self.blas, "cublasCreate_v2", [C.POINTER(ptr)])
        self._blas_destroy = self._bind(self.blas, "cublasDestroy_v2", [ptr])
        self._blas_version = self._bind(
            self.blas, "cublasGetVersion_v2", [ptr, C.POINTER(cint)]
        )
        self._blas_math = self._bind(self.blas, "cublasSetMathMode", [ptr, cint])
        self._sgemm = self._bind(
            self.blas, "cublasSgemm_v2",
            [ptr, cint, cint, cint, cint, cint, ptr, ptr, cint, ptr, cint, ptr, ptr, cint],
        )
        self._gemm_ex = self._bind(
            self.blas, "cublasGemmEx",
            [
                ptr, cint, cint, cint, cint, cint, ptr, ptr, cint, cint,
                ptr, cint, cint, ptr, ptr, cint, cint, cint, cint,
            ],
        )
        count = cint()
        self.check(self._cuda_count(C.byref(count)), "cudaGetDeviceCount")
        if count.value != 1:
            raise RuntimeError(f"Expected one CUDA device, found {count.value}")
        self.check(self._cuda_set(0), "cudaSetDevice")
        self.handle = ptr()
        self.check(self._blas_create(C.byref(self.handle)), "cublasCreate")

    @staticmethod
    def _bind(dll, name, argtypes):
        function = getattr(dll, name)
        function.restype = C.c_int
        function.argtypes = argtypes
        return function

    @staticmethod
    def check(code: int, action: str) -> None:
        if code != 0:
            raise RuntimeError(f"{action} failed with code {code}")

    def versions(self) -> dict[str, int]:
        runtime = C.c_int()
        driver = C.c_int()
        blas = C.c_int()
        self.check(self._runtime_version(C.byref(runtime)), "cudaRuntimeGetVersion")
        self.check(self._driver_version(C.byref(driver)), "cudaDriverGetVersion")
        self.check(self._blas_version(self.handle, C.byref(blas)), "cublasGetVersion")
        return {
            "cuda_runtime": runtime.value,
            "cuda_driver_api": driver.value,
            "cublas": blas.value,
        }

    def malloc(self, nbytes: int) -> C.c_void_p:
        pointer = C.c_void_p()
        self.check(self._cuda_malloc(C.byref(pointer), nbytes), "cudaMalloc")
        return pointer

    def measure(
        self, name: str, datatype: int, one_bits: int,
        math_mode: int, compute_type: int,
    ) -> dict:
        count = N * N
        element_size = 4 if datatype == 0 else 2
        pattern = struct.pack("<I" if element_size == 4 else "<H", one_bits)
        host = pattern * count
        allocations = []
        events = []
        try:
            a = self.malloc(len(host)); allocations.append(a)
            b = self.malloc(len(host)); allocations.append(b)
            output = self.malloc(count * 4); allocations.append(output)
            source = C.c_char_p(host)
            self.check(self._cuda_memcpy(a, source, len(host), 1), "cudaMemcpy A H2D")
            self.check(self._cuda_memcpy(b, source, len(host), 1), "cudaMemcpy B H2D")
            del source, host
            self.check(self._blas_math(self.handle, math_mode), "cublasSetMathMode")
            alpha = C.c_float(1.0)
            beta = C.c_float(0.0)

            def gemm() -> None:
                if name == "fp32_pedantic":
                    code = self._sgemm(
                        self.handle, 0, 0, N, N, N, C.byref(alpha), a, N,
                        b, N, C.byref(beta), output, N,
                    )
                    self.check(code, "cublasSgemm")
                else:
                    code = self._gemm_ex(
                        self.handle, 0, 0, N, N, N, C.byref(alpha),
                        a, datatype, N, b, datatype, N, C.byref(beta),
                        output, 0, N, compute_type, 99,
                    )
                    self.check(code, "cublasGemmEx")

            end = time.perf_counter() + WARMUP_SECONDS
            while time.perf_counter() < end:
                gemm()
                self.check(self._cuda_sync(), "warmup sync")
            start = C.c_void_p(); stop = C.c_void_p()
            self.check(self._event_create(C.byref(start)), "cudaEventCreate start")
            events.append(start)
            self.check(self._event_create(C.byref(stop)), "cudaEventCreate stop")
            events.append(stop)
            samples = []
            for _ in range(SAMPLES):
                self.check(self._event_record(start, None), "cudaEventRecord start")
                gemm()
                self.check(self._event_record(stop, None), "cudaEventRecord stop")
                self.check(self._event_sync(stop), "cudaEventSynchronize")
                milliseconds = C.c_float()
                self.check(
                    self._event_elapsed(C.byref(milliseconds), start, stop),
                    "cudaEventElapsedTime",
                )
                samples.append(milliseconds.value)
            first = C.c_float(); last = C.c_float()
            self.check(self._cuda_memcpy(C.byref(first), output, 4, 2), "first D2H")
            last_address = C.c_void_p(output.value + (count - 1) * 4)
            self.check(self._cuda_memcpy(C.byref(last), last_address, 4, 2), "last D2H")
            if first.value != N or last.value != N:
                raise RuntimeError(f"{name}: GEMM reference failed: {first.value}, {last.value}")
            median_ms = statistics.median(samples)
            return {
                "name": name, "n": N, "samples": SAMPLES,
                "warmup_seconds": WARMUP_SECONDS,
                "median_ms": median_ms, "min_ms": min(samples), "max_ms": max(samples),
                "tflops": 2 * N**3 / (median_ms * 1e9),
                "input_type": datatype, "output_type": 0,
                "compute_type": compute_type, "math_mode": math_mode,
                "reference_checked": True,
            }
        finally:
            for event in events:
                self.check(self._event_destroy(event), "cudaEventDestroy")
            for pointer in allocations:
                self.check(self._cuda_free(pointer), "cudaFree")

    def close(self) -> None:
        self.check(self._blas_destroy(self.handle), "cublasDestroy")


def write_json(path: Path, data: dict) -> None:
    with path.open("x", encoding="utf-8") as stream:
        json.dump(data, stream, indent=2, ensure_ascii=False)
        stream.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", required=True, choices=("before", "after"))
    parser.add_argument(
        "--output-root", type=Path, default=ROOT / "results" / "rtx3060ti"
    )
    args = parser.parse_args()
    idle = check_idle()
    library_hashes = {
        path.name: sha256(path)
        for path in (CUDART_PATH, BLAS_PATH, BLAS_LT_PATH)
    }
    cuda = CudaBlas()
    versions = cuda.versions()
    if versions["cuda_runtime"] != 12060 or versions["cublas"] != 120600:
        raise RuntimeError(f"Unexpected CUDA/cuBLAS versions: {versions}")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = args.output_root / f"{stamp}-{args.phase}-{uuid4().hex[:8]}"
    output.mkdir(parents=True, exist_ok=False)
    environment = {
        "phase": args.phase,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "script_sha256": sha256(Path(__file__)),
        "python": sys.version.split()[0],
        "dll_sha256": library_hashes,
        "gpu_name": GPU_NAME,
        "gpu_pci_id": GPU_ID,
        "gpu_subsystem_id": SUBSYSTEM_ID,
        "gpu_bus_id": BUS_ID,
        "matrix_n": N,
        "warmup_seconds": WARMUP_SECONDS,
        "samples_per_mode": SAMPLES,
        "trials": TRIALS,
        "versions": versions,
        "idle_samples": idle,
        "method": "cuBLAS 12.6 FP32 output, CUDA event timing, same GEMM modes as upstream",
    }
    write_json(output / "environment.json", environment)
    trials = []
    try:
        for trial_number in range(1, TRIALS + 1):
            trial = {"number": trial_number, "gpu_before": gpu_state(), "benchmarks": []}
            for mode in MODES:
                trial["benchmarks"].append(cuda.measure(*mode))
            trial["gpu_after"] = gpu_state()
            write_json(output / f"trial-{trial_number}.json", trial)
            trials.append(trial)
    finally:
        cuda.close()
    summary = {
        "phase": args.phase,
        "environment": environment,
        "gpu_after": gpu_state(),
        "results": [],
    }
    for name, *_ in MODES:
        values = sorted(
            next(row["tflops"] for row in trial["benchmarks"] if row["name"] == name)
            for trial in trials
        )
        summary["results"].append({
            "name": name, "median_tflops": values[1],
            "min_tflops": values[0], "max_tflops": values[2],
        })
    write_json(output / "summary.json", summary)
    print(f"Saved {args.phase} measurement: {output / 'summary.json'}")
    for item in summary["results"]:
        print(f"{item['name']}: {item['median_tflops']:.2f} TFLOPS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
