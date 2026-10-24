# GPL-2.0-only. Prove the built EFI is the read-only diagnostic variant.
param([string]$Clang='clang')
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
 $dir='build/selector-timeline'
 $manifest=Get-Content -LiteralPath (Join-Path $dir 'manifest.json') -Raw | ConvertFrom-Json
 $pe=Get-Content -LiteralPath (Join-Path $dir 'pe-verification.json') -Raw | ConvertFrom-Json
 $map=Get-Content -LiteralPath (Join-Path $dir 'SELECTOR-TIMELINE.map') -Raw
 $efi=Join-Path $dir 'SELECTOR-TIMELINE.EFI'
 if($manifest.Mode -cne 'rtx3060ti-read-only-selector-timeline' -or
    $manifest.CanUnlock -ne $false -or $manifest.CanDetach -ne $false -or
    $manifest.WritesFirmwareVariables -ne $false -or
    $manifest.EfiSha256 -ine (Get-FileHash -LiteralPath $efi -Algorithm SHA256).Hash -or
    $pe.machine -cne 'AMD64' -or $pe.subsystem -ne 10 -or
    $pe.imports -ne 0 -or $pe.delay_imports -ne 0 -or
    !$pe.nx -or !$pe.dynamic_base) {
  throw 'Built selector timeline identity or PE safety properties failed.'
 }
 foreach($symbol in @('GuSelectorTimelineBegin','GuSelectorTimelineWait',
                     'GuSelectorTimelineSample','GuSelectorTimelineProm','GuCaptureGraph')) {
  if($map -notmatch ('(?m)^\s*[0-9a-f]+:[0-9a-f]+\s+'+$symbol+'\s')) {
   throw "Missing timeline function in final PE map: $symbol"
  }
 }
 foreach($symbol in @('GuFullFlow','GuReleaseGop','GuProbeGpu','GuWrite32','GuFlr')) {
  if($map -match ('(?m)^\s*[0-9a-f]+:[0-9a-f]+\s+'+$symbol+'\s')) {
   throw "Effecting or legacy probe function linked into read-only EFI: $symbol"
  }
 }
 $source=Get-Content -LiteralPath 'selector-timeline.c' -Raw
 foreach($pattern in @('->\s*Mem\.Write','->\s*Pci\.Write','->\s*Attributes\s*\(',
                       '->\s*DisconnectController\s*\(','->\s*ConnectController\s*\(',
                       '->\s*SetVariable\s*\(','->\s*ResetSystem\s*\(',
                       '->\s*LoadImage\s*\(','->\s*StartImage\s*\(')) {
  if($source -match $pattern){throw "Effecting call found in timeline source: $pattern"}
 }
 $args=@('-target','x86_64-pc-windows-msvc','-std=c11','-ffreestanding',
         '-fshort-wchar','-DGU_DIAGNOSTIC_ONLY','-DGU_SELECTOR_TIMELINE',
         '-DGU_FULL_UNLOCK','-DGU_PROFILE_Z690_3060TI',
         '-I','../../deps/edk2/MdePkg/Include',
         '-I','../../deps/edk2/MdePkg/Include/X64',
         '-c','selector-timeline.c','-o',(Join-Path $dir 'must-reject.obj'))
 $rejected=(& $Clang @args 2>&1 | Out-String)
 if($LASTEXITCODE -eq 0 -or $rejected -notmatch 'separate read-only Z690 diagnostic image') {
  throw 'Mixed timeline and full-unlock compile was not rejected by the guard.'
 }
 Write-Output 'PASS dedicated PE has no imports or unlock/detach functions; source has no device writes; mixed build rejected.'
} finally {Pop-Location}
