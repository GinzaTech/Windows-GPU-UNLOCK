param(
    [ValidateSet('Menu', 'Archive', 'MeasureBefore', 'MeasureAfter', 'Compare', 'ShowSummary', 'OpenResults', 'GpuState')]
    [string]$Action = 'Menu',
    [string]$BeforeSummary,
    [string]$AfterSummary,
    [string]$SummaryPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$measureScript = Join-Path $PSScriptRoot 'measure.py'
$compareScript = Join-Path $PSScriptRoot 'compare.py'
$setupScript = Join-Path $PSScriptRoot 'setup.ps1'
$resultsRoot = Join-Path $repoRoot 'benchmark\results\rtx3060ti'
$historicalBefore = Join-Path $PSScriptRoot 'baseline\20261024T164051Z-before-19d2e439\summary.json'
$historicalAfter = Join-Path $resultsRoot '20261024T183204Z-after-84d1f28f\summary.json'
$historicalReport = Join-Path $repoRoot 'docs\WINDOWS-RTX3060TI-RESULTS.vi.md'
$modeLabels = @{
    fp32_pedantic = 'FP32'
    tf32_tensor_fp32_accumulate = 'TF32 Tensor'
    fp16_tensor_fp32_accumulate = 'FP16 Tensor'
    bf16_tensor_fp32_accumulate = 'BF16 Tensor'
}

function Get-PythonPath {
    $command = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'Khong tim thay Python. Cai Python 3.12 va mo lai cong cu.'
    }
    return $command.Source
}

function Resolve-SummaryPath([string]$PathText) {
    $clean = $PathText.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $clean -PathType Leaf)) {
        throw "Khong tim thay summary.json: $clean"
    }
    return (Resolve-Path -LiteralPath $clean).Path
}

function Show-Summary([string]$PathText) {
    $path = Resolve-SummaryPath $PathText
    $summary = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $summary.results -or -not $summary.environment) {
        throw "Khong dung dinh dang summary.json: $path"
    }
    $idle = @($summary.environment.idle_samples)[-1]
    Write-Host "`nKet qua: $path" -ForegroundColor Cyan
    Write-Host "Nhan: $($summary.phase) | GPU: $($summary.environment.gpu_name) | Driver: $($idle.driver_version) | Gioi han dien: $($idle.'power.limit') W"
    $rows = foreach ($item in $summary.results) {
        [pscustomobject]@{
            CheDo = $modeLabels[$item.name]
            MedianTFLOPS = [math]::Round([double]$item.median_tflops, 2)
            ThapNhat = [math]::Round([double]$item.min_tflops, 2)
            CaoNhat = [math]::Round([double]$item.max_tflops, 2)
        }
    }
    $rows | Format-Table -AutoSize | Out-String -Width 140 | Write-Host
    $after = $summary.gpu_after
    if ($after) {
        Write-Host "Cuoi phep do: $($after.'power.draw') W | $($after.'temperature.gpu') C | SM $($after.'clocks.current.sm') MHz | GPU $($after.'utilization.gpu')%"
    }
}

function Show-HistoricalComparison {
    $before = Resolve-SummaryPath $historicalBefore
    Write-Host "`nSo lieu A/B da luu tu 24/10/2026. Lenh nay KHONG tai GPU." -ForegroundColor Yellow
    if (Test-Path -LiteralPath $historicalAfter -PathType Leaf) {
        $python = Get-PythonPath
        $after = Resolve-SummaryPath $historicalAfter
        Write-Host "Before: $before"
        Write-Host "After : $after"
        & $python $compareScript $before $after
        if ($LASTEXITCODE -ne 0) { throw "So sanh that bai (ma $LASTEXITCODE)." }
        return
    }
    Write-Host 'Tep after goc la capture rieng, khong nam trong ban ma nguon cong khai.' -ForegroundColor Yellow
    Write-Host 'Bang duoi day chi la so lieu da cong bo; khong phai so sanh lai hai tep tren may nay.'
    $rows = @(Get-Content -LiteralPath $historicalReport -Encoding UTF8 |
        Where-Object { $_ -match '^\| (FP32|TF32|FP16|BF16) ' })
    if ($rows.Count -ne 4) { throw "Khong doc duoc bang so lieu trong $historicalReport" }
    Write-Host '| Che do | Before TFLOPS | Diagnostic TFLOPS | After TFLOPS | After/Before |'
    $rows | ForEach-Object { Write-Host $_ }
    Write-Host "Bao cao: $historicalReport"
}

function Get-LatestSummary([string]$Phase) {
    if (-not (Test-Path -LiteralPath $resultsRoot -PathType Container)) { return $null }
    $directories = Get-ChildItem -LiteralPath $resultsRoot -Directory |
        Where-Object { $_.Name -like "*-$Phase-*" } |
        Sort-Object LastWriteTimeUtc -Descending
    foreach ($directory in $directories) {
        $candidate = Join-Path $directory.FullName 'summary.json'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Read-SummaryPath([string]$Label, [string]$DefaultPath) {
    if ($DefaultPath) { Write-Host "$Label mac dinh: $DefaultPath" }
    else { Write-Host "${Label}: dan duong dan summary.json can so sanh" }
    $typed = Read-Host 'Nhan Enter de dung mac dinh, hoac dan duong dan summary.json'
    if ([string]::IsNullOrWhiteSpace($typed)) {
        if (-not $DefaultPath) { throw "Can duong dan summary.json cho $Label." }
        return $DefaultPath
    }
    return $typed
}

function Show-SavedSummary([string]$PathText) {
    if ([string]::IsNullOrWhiteSpace($PathText)) {
        $default = Get-LatestSummary 'after'
        if (-not $default) { $default = Get-LatestSummary 'before' }
        if (-not $default) { $default = $historicalBefore }
        $PathText = Read-SummaryPath 'Ket qua' $default
    }
    Show-Summary $PathText
}

function Invoke-Comparison([string]$BeforePath, [string]$AfterPath) {
    $python = Get-PythonPath
    if ([string]::IsNullOrWhiteSpace($BeforePath)) {
        $defaultBefore = Get-LatestSummary 'before'
        if (-not $defaultBefore) { $defaultBefore = $historicalBefore }
        $BeforePath = Read-SummaryPath 'Before' $defaultBefore
    }
    if ([string]::IsNullOrWhiteSpace($AfterPath)) {
        $defaultAfter = Get-LatestSummary 'after'
        if (-not $defaultAfter -and (Test-Path -LiteralPath $historicalAfter -PathType Leaf)) {
            $defaultAfter = $historicalAfter
        }
        $AfterPath = Read-SummaryPath 'After' $defaultAfter
    }
    $before = Resolve-SummaryPath $BeforePath
    $after = Resolve-SummaryPath $AfterPath
    Write-Host "`nSo sanh hai tep duoc chon:" -ForegroundColor Cyan
    Write-Host "Before: $before"
    Write-Host "After : $after"
    Write-Warning 'Nhan before/after khong chung minh may da unlock. Can log UEFI cua dung lan boot va dieu kien dien/xung giong nhau.'
    & $python $compareScript $before $after
    if ($LASTEXITCODE -ne 0) { throw "So sanh that bai (ma $LASTEXITCODE)." }
}

function Assert-BenchmarkPackages {
    $packages = Join-Path $repoRoot 'benchmark\packages\rtx3060ti'
    $files = @(
        (Join-Path $packages 'cuda_cudart\cuda_cudart-windows-x86_64-12.6.37-archive\bin\cudart64_12.dll'),
        (Join-Path $packages 'libcublas\libcublas-windows-x86_64-12.6.0.22-archive\bin\cublas64_12.dll'),
        (Join-Path $packages 'libcublas\libcublas-windows-x86_64-12.6.0.22-archive\bin\cublasLt64_12.dll')
    )
    if (@($files | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -eq 0) { return }
    Write-Host 'Thieu CUDA/cuBLAS DLL. setup.ps1 se tai tep NVIDIA da khoa SHA-256.' -ForegroundColor Yellow
    $answer = Read-Host 'Chay setup bay gio? (y/N)'
    if ($answer -notin @('y', 'Y')) { throw 'Chua co DLL. Khong chay GPU benchmark.' }
    & $setupScript
    $missing = @($files | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missing.Count -gt 0) {
        throw "Setup chua tao du CUDA DLL. Co the thu muc goi da giai nen do. Kiem tra: $($missing -join ', ')"
    }
}

function Invoke-Measurement([string]$Phase) {
    $python = Get-PythonPath
    Assert-BenchmarkPackages
    if (-not (Test-Path -LiteralPath $resultsRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $resultsRoot -Force | Out-Null
    }
    $existing = @(Get-ChildItem -LiteralPath $resultsRoot -Directory | ForEach-Object FullName)
    Write-Host "`nDo phien Windows hien tai voi nhan '$Phase'." -ForegroundColor Cyan
    Write-Warning 'Nhan nay KHONG tu kiem tra unlock. Truoc khi so sanh, dua GPU ve xung goc, dung cung 200 W/driver va doi chieu log UEFI cua lan boot nay.'
    try {
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        Write-Host "Windows boot: $boot"
    } catch {
        Write-Warning "Khong doc duoc thoi gian boot: $_"
    }
    Write-Host 'Dang do 3 luot x 4 che do GEMM. Co the mat vai phut; dung chay game/video trong luc do.'
    & $python $measureScript --phase $Phase
    if ($LASTEXITCODE -ne 0) { throw "Benchmark that bai (ma $LASTEXITCODE). Kiem tra thu muc ket qua neu da duoc tao." }
    $newDirectories = @(Get-ChildItem -LiteralPath $resultsRoot -Directory |
        Where-Object { $_.FullName -notin $existing -and $_.Name -like "*-$Phase-*" })
    $summaries = @($newDirectories | ForEach-Object {
        $candidate = Join-Path $_.FullName 'summary.json'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidate }
    })
    if ($summaries.Count -ne 1) {
        Write-Warning 'Khong xac dinh duoc duy nhat tep moi. Hay mo thu muc ket qua de xem duong dan do Python in ra.'
        return
    }
    Show-Summary $summaries[0]
    Write-Host "Tep goc: $($newDirectories[0].FullName)\environment.json va trial-1..3.json"
}

function Open-ResultsFolder {
    if (-not (Test-Path -LiteralPath $resultsRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $resultsRoot -Force | Out-Null
    }
    Start-Process -FilePath 'explorer.exe' -ArgumentList @($resultsRoot) -WindowStyle Normal
    Write-Host "Da mo: $resultsRoot"
}

function Show-GpuState {
    $smi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if (-not $smi) { throw 'Khong tim thay nvidia-smi.exe. Kiem tra driver NVIDIA.' }
    Write-Host "`nThong so GPU tuc thoi (khong tai GPU):" -ForegroundColor Cyan
    & $smi.Source --query-gpu=name,pci.bus_id,driver_version,power.limit,power.draw,temperature.gpu,clocks.current.sm,clocks.current.memory,utilization.gpu,memory.used --format=csv
    if ($LASTEXITCODE -ne 0) { throw "nvidia-smi that bai (ma $LASTEXITCODE)." }
    Write-Host 'Anh chup tuc thoi khong chung minh unlock hay offset xung da ve mac dinh.'
}

if ($Action -ne 'Menu') {
    switch ($Action) {
        'Archive' { Show-HistoricalComparison }
        'MeasureBefore' { Invoke-Measurement 'before' }
        'MeasureAfter' { Invoke-Measurement 'after' }
        'Compare' { Invoke-Comparison $BeforeSummary $AfterSummary }
        'ShowSummary' { Show-SavedSummary $SummaryPath }
        'OpenResults' { Open-ResultsFolder }
        'GpuState' { Show-GpuState }
    }
    exit 0
}

Write-Host 'RTX 3060 Ti - CUDA/cuBLAS compute benchmark' -ForegroundColor Cyan
Write-Host "Thu muc du an: $repoRoot"
while ($true) {
    Write-Host "`n1. Xem so lieu A/B da do (khong tai GPU)"
    Write-Host '2. Do phien hien tai, gan nhan BEFORE'
    Write-Host '3. Do phien hien tai, gan nhan AFTER'
    Write-Host '4. So sanh hai tep summary.json'
    Write-Host '5. Xem mot tep summary.json da luu'
    Write-Host '6. Mo thu muc ket qua'
    Write-Host '7. Xem thong so GPU hien tai (dien, nhiet, xung, tai)'
    Write-Host '0. Thoat'
    $choice = Read-Host 'Chon'
    if ($choice -eq '0') { break }
    try {
        switch ($choice) {
            '1' { Show-HistoricalComparison }
            '2' { Invoke-Measurement 'before' }
            '3' { Invoke-Measurement 'after' }
            '4' { Invoke-Comparison $BeforeSummary $AfterSummary }
            '5' { Show-SavedSummary $SummaryPath }
            '6' { Open-ResultsFolder }
            '7' { Show-GpuState }
            default { Write-Warning 'Lua chon khong hop le.' }
        }
    } catch {
        Write-Host "Loi: $_" -ForegroundColor Red
    }
    Read-Host 'Nhan Enter de quay lai menu' | Out-Null
}
