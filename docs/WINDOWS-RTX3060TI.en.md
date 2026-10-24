# Install the experimental RTX 3060 Ti Windows build

[Tiếng Việt](WINDOWS-RTX3060TI.vi.md) · [Performance report](WINDOWS-RTX3060TI-RESULTS.en.md)

## Verified scope

This Windows build completed **one hardware run** on an ASUS TUF GAMING Z690-PLUS WIFI D4, BIOS 2602, Windows 11 x64, and RTX 3060 Ti `10DE:2489 / 1043:8827` with VBIOS `94.04.6B.00.11`. The UEFI transaction completed, Windows recovered the NVIDIA display, and a CUDA measurement showed higher Tensor throughput. See the [performance report and evidence limits](WINDOWS-RTX3060TI-RESULTS.en.md).

`windows/Install-RTX3060Ti.ps1` automates validation, building, and registration of a **firmware F8 test entry** for the verified hardware profile. The installer checks the exact board, BIOS, GPU PCI IDs and working status, and both ESPs; the EFI checks PROM and firmware topology when it runs. The VBIOS in the table is an **observed value**, not an installer preflight gate. There is no evidence that every Windows PC with a 3060 Ti can run this profile. A built EFI is also specific to the local partition GUIDs and cannot be copied unchanged to another PC.

| Configuration | Status |
| --- | --- |
| ASUS TUF GAMING Z690-PLUS WIFI D4, BIOS 2602, RTX 3060 Ti `10DE:2489 / 1043:8827`, VBIOS `94.04.6B.00.11` | One UEFI run, Windows boot, and CUDA measurement confirmed on the test PC. |
| Another PC with the same board, BIOS, and GPU PCI IDs | Untested; installer checks may pass, but EFI preflight may still stop. |
| Different board, BIOS, or GPU PCI IDs | Untested; the installer rejects the different profile. |

## Prerequisites

- Back up data and confirm you can reach ASUS F8 → **Windows Boot Manager**. Keep a keyboard and monitor connected to the RTX card.
- x64 UEFI; Secure Boot **Off** because the experimental EFI is unsigned. Windows C: must be fully decrypted with BitLocker protection Off. The installer checks these states and does not change them. Retain the BitLocker recovery key before changing BIOS settings.
- A **separate** GPT FAT32 EFI System Partition (ESP), at least 1 GiB, with an unused drive letter such as `U:`. Never use, format, or delete the ESP that contains Windows Boot Manager. The installer does not create, shrink, or format partitions.
- Administrator PowerShell, Git if cloning the source, Python 3.9+, and LLVM `clang`/`lld-link` 20.1.8. Prepare the five NVIDIA firmware assets from legitimate original inputs using the [source and hash instructions](ASSETS.en.md). The source release excludes firmware, PROM, drivers, and machine-specific EFI binaries.
- For a performance comparison, install the hash-pinned CUDA/cuBLAS DLLs using `benchmark/rtx3060ti/setup.ps1` before collecting the baseline.

In Administrator PowerShell, inspect the machine and identify the **two distinct** ESPs:

```powershell
Get-CimInstance Win32_BaseBoard | Select-Object Product
Get-CimInstance Win32_BIOS | Select-Object SMBIOSBIOSVersion
nvidia-smi --query-gpu=name,pci.device_id,pci.sub_device_id,vbios_version --format=csv,noheader
Get-Partition | Format-Table DiskNumber,PartitionNumber,DriveLetter,Size,GptType,Guid,IsSystem
Get-Volume -DriveLetter U | Format-List FileSystem,Size,Path
Get-BitLockerVolume -MountPoint C: | Format-List VolumeStatus,ProtectionStatus
Confirm-SecureBootUEFI
```

Proceed only if `U:` is the prepared **separate** ESP and `IsSystem=False`. The installer discovers and checks the Windows ESP (`IsSystem=True`). If this machine differs from the profile above, stop after `-Plan`; do not weaken the hardware checks to force installation.

## Get the source and measure a baseline

Open the checkout containing this guide and `windows/Install-RTX3060Ti.ps1`; an older GitHub default branch may not contain the installer yet. From the checkout root, run:

```powershell
if (-not (Test-Path .\windows\Install-RTX3060Ti.ps1)) {
  throw 'This checkout does not contain the RTX 3060 Ti installer.'
}
# Place the five .bin files in .\assets following docs/ASSETS.en.md.
.\benchmark\rtx3060ti\setup.ps1
python .\benchmark\rtx3060ti\measure.py --phase before
```

Keep `measure.py`, CUDA libraries, driver, power limit, resolution, and background load comparable between runs. The baseline produces `benchmark/results/rtx3060ti/<timestamp>-before-.../summary.json`.

## Plan and install

This example uses the separate `U:` ESP and LLVM tools in `PATH`:

```powershell
.\windows\Install-RTX3060Ti.ps1 -Plan -UnlockDriveLetter U

# Optional: build and verify hashes without staging on the ESP.
.\windows\Install-RTX3060Ti.ps1 -BuildOnly -UnlockDriveLetter U `
  -Clang clang -LldLink lld-link -Python python

# Continue only when the plan identifies the correct PC and both ESPs; Install validates the five assets.
.\windows\Install-RTX3060Ti.ps1 -Install -UnlockDriveLetter U `
  -AssetsDirectory '.\assets' `
  -Clang clang -LldLink lld-link -Python python
```

`-Plan` (also the default mode) inspects and prints the plan only. `-BuildOnly` builds without installing; `-Install` builds both EFIs from the local configuration, checks their hashes, stages them on the separate ESP, and adds **GPU Headless UNLOCK - EXPERIMENTAL** to the firmware menu. Re-running `-Install` with the identical installed pair verifies it; a pair with different hashes is rejected. Windows Boot Manager remains first. Installation does not reboot and does not make unlock the default on every startup. Retain local configuration and BCD backups for recovery; they are not release files.

## Run the hardware test

After measuring the baseline, save work and **shut down fully**. Power on, press F8 at the ASUS screen, and select **GPU Headless UNLOCK - EXPERIMENTAL**. Do not select the read-only diagnostic entry. The child runs once automatically; no U key is needed. The RTX display may go black while the UEFI driver is released, then Windows starts directly after successful cleanup.

If you see `STOP / POWER OFF` or the screen remains stuck for more than three minutes, hold the power button to turn the machine off. Power on and select F8 → Windows Boot Manager; do not retry unlock in the same firmware session. Reaching Windows **alone** is not proof: the child `AUTO......\REPORT.TXT` must record `transaction result=0`, `FLR=1`, `clean=1`, followed by a working driver and an after measurement.

After Windows starts, in Administrator PowerShell:

```powershell
Get-ChildItem U:\RTX3090-UNLOCK -Recurse -Filter REPORT.TXT |
  Sort-Object LastWriteTime -Descending |
  Select-Object FullName,LastWriteTime
.\windows\Install-RTX3060Ti.ps1 -RecoverWindowsFirst
nvidia-smi
```

Open the `REPORT.TXT` from the current run to inspect its result lines. The older `Collect-Headless3060Ti.ps1` research script pins the test machine's identifiers and is not a general collector.

Only after the report confirms clean completion and the GPU works in Windows, use the **same** `measure.py` for the after run:

```powershell
python .\benchmark\rtx3060ti\measure.py --phase after
$before = Get-ChildItem .\benchmark\results\rtx3060ti -Directory |
  Where-Object Name -Like '*-before-*' | Sort-Object Name -Descending | Select-Object -First 1
$after = Get-ChildItem .\benchmark\results\rtx3060ti -Directory |
  Where-Object Name -Like '*-after-*' | Sort-Object Name -Descending | Select-Object -First 1
python .\benchmark\rtx3060ti\compare.py `
  (Join-Path $before.FullName 'summary.json') `
  (Join-Path $after.FullName 'summary.json')
```

If the before run is missing or its environment differs, remeasure a comparable pair; a read-only diagnostic run is not an unlocked after result.

## Recovery and limits

Windows Boot Manager stays the default. If you need to restore its priority after a later change, run `windows/Install-RTX3060Ti.ps1 -RecoverWindowsFirst` in Administrator PowerShell. Recovery does not delete the ESP, EFI files, assets, or logs. An unprofiled PC will be refused by the installer; supporting it requires read-only diagnosis, a separate hardware profile, and controlled device testing.

The reported result is CUDA GEMM, not game FPS. Repeated default automatic startup, sleep/resume, and long-term stability have not been tested. Do not infer a performance gain from raising a power limit or replacing VBIOS based on this report.
