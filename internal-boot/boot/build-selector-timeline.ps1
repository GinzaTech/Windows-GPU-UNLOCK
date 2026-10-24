# GPL-2.0-only. Build a separate read-only Z690 selector timeline; no ESP/BCD changes.
param([string]$Clang='clang',[string]$LldLink='lld-link',[string]$Python='python')
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
 $systemEsp=@(Get-Partition | Where-Object {
  $_.IsSystem -and $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
 })
 if($systemEsp.Count -ne 1 -or !$systemEsp[0].Guid){throw 'Expected exactly one current Windows EFI partition'}
 $gpu=@(Get-CimInstance Win32_VideoController | Where-Object {
  $_.PNPDeviceID -match 'VEN_10DE&DEV_2489&SUBSYS_88271043'
 })
 if($gpu.Count -ne 1){throw 'Expected this machine RTX 3060 Ti (10DE:2489, 1043:8827)'}
 function GuidC([guid]$value) {
  $b=$value.ToByteArray()
  $tail=($b[8..15] | ForEach-Object {'0x{0:x2}' -f $_}) -join ','
  return ('{{0x{0:x8},0x{1:x4},0x{2:x4},{{{3}}}}}' -f
   [BitConverter]::ToUInt32($b,0),[BitConverter]::ToUInt16($b,4),
   [BitConverter]::ToUInt16($b,6),$tail)
 }
 $guid=GuidC ([guid]$systemEsp[0].Guid)
 @(
  '/* Local read-only diagnostic configuration; never used for unlocking. */',
  ('#define GU_INTERNAL_PARTITION_INITIALIZER '+$guid),
  ('#define GU_WINDOWS_PARTITION_INITIALIZER '+$guid)
 ) | Set-Content -LiteralPath diagnostic-config.h -Encoding ascii
 $out='build/selector-timeline'
 New-Item -ItemType Directory -Path $out -Force | Out-Null
 $sources=@('handoff.c','diagnostic.c','selector-timeline.c','../efi_runtime.c','../unlock/sha256.c')
 $objects=@()
 foreach($source in $sources) {
  $obj=Join-Path $out ([IO.Path]::GetFileNameWithoutExtension($source)+'.obj')
  & $Clang -target x86_64-pc-windows-msvc -std=c11 -ffreestanding -fno-builtin -fno-stack-protector -mno-red-zone -fshort-wchar -Os -Wall -Wextra -Werror -DGU_DIAGNOSTIC_ONLY -DGU_DIAGNOSTIC_SAME_ESP -DGU_SELECTOR_TIMELINE -DGU_PROFILE_Z690_3060TI -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 -c $source -o $obj
  if($LASTEXITCODE -ne 0){throw "Compile failed: $source"}
  $objects+=$obj
 }
 $efi=Join-Path $out 'SELECTOR-TIMELINE.EFI'
 $map=Join-Path $out 'SELECTOR-TIMELINE.map'
 & $LldLink /nologo /nodefaultlib /subsystem:efi_application /entry:efi_main /machine:x64 /base:0 /dynamicbase /nxcompat /timestamp:0 /opt:ref /opt:icf "/map:$map" "/out:$efi" @objects
 if($LASTEXITCODE -ne 0){throw 'Selector timeline link failed'}
 & $Python ../unlock/verify_pe.py $efi $map --output (Join-Path $out 'pe-verification.json')
 if($LASTEXITCODE -ne 0){throw 'Selector timeline PE verification failed'}
 $sourceManifest=@(($sources+@('diagnostic.h','selector-timeline.h','media.h','diagnostic-config.h')) | ForEach-Object {
  [ordered]@{Path=$_;Sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}
 })
 [ordered]@{
  HardwareTested=$false;Mode='rtx3060ti-read-only-selector-timeline'
  TargetPci='10de:2489';TargetSubsystem='1043:8827'
  WindowsEspGuid=[string]$systemEsp[0].Guid
  CanUnlock=$false;CanDetach=$false;WritesFirmwareVariables=$false
  SelectorSamples=@('early','after-5s','post-graph','pre-prom','post-prom')
  PromBytes=1048576;PromReadWidth='EfiPciIoWidthUint8';PromChunkBytes=65536
  EfiSha256=(Get-FileHash -LiteralPath $efi -Algorithm SHA256).Hash
  BuiltUtc=[DateTime]::UtcNow.ToString('o');Sources=$sourceManifest
 } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'manifest.json') -Encoding utf8
 Write-Output "Read-only selector timeline built: $efi"
} finally {Pop-Location}
