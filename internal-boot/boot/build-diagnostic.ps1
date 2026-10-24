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
 New-Item -ItemType Directory -Path build/diagnostic -Force | Out-Null
 $sources=@('handoff.c','diagnostic.c','../efi_runtime.c','probe.c','../unlock/sha256.c')
 $objects=@()
 foreach($source in $sources) {
  $obj='build/diagnostic/'+[IO.Path]::GetFileNameWithoutExtension($source)+'.obj'
  & $Clang -target x86_64-pc-windows-msvc -std=c11 -ffreestanding -fno-builtin -fno-stack-protector -mno-red-zone -fshort-wchar -Os -Wall -Wextra -Werror -DGU_DIAGNOSTIC_ONLY -DGU_DIAGNOSTIC_PROBE -DGU_DIAGNOSTIC_SAME_ESP -DGU_DIAGNOSTIC_TARGET_PCI_ID=0x248910deU -DGU_DIAGNOSTIC_TARGET_SUBSYSTEM=0x88271043U -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 -c $source -o $obj
  if($LASTEXITCODE -ne 0){throw "Compile failed: $source"}
  $objects+=$obj
 }
 & $LldLink /nologo /nodefaultlib /subsystem:efi_application /entry:efi_main /machine:x64 /base:0 /dynamicbase /nxcompat /timestamp:0 /opt:ref /opt:icf /map:build/diagnostic/DIAGNOSTIC.map /out:build/diagnostic/DIAGNOSTIC.EFI @objects
 if($LASTEXITCODE -ne 0){throw 'Diagnostic link failed'}
 & $Python ../unlock/verify_pe.py build/diagnostic/DIAGNOSTIC.EFI build/diagnostic/DIAGNOSTIC.map --output build/diagnostic/pe-verification.json
 if($LASTEXITCODE -ne 0){throw 'Diagnostic PE verification failed'}
 $sourceManifest=@(($sources+@('diagnostic.h','probe.h','media.h','diagnostic-config.h')) | ForEach-Object {
  [ordered]@{Path=$_;Sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}
 })
 [ordered]@{
  HardwareTested=$false;Mode='rtx3060ti-read-only-probe-then-normal-windows'
  TargetPci='10de:2489';TargetSubsystem='1043:8827'
  WindowsEspGuid=[string]$systemEsp[0].Guid;CanUnlock=$false
  CanDetach=$false;WritesFirmwareVariables=$false
  EfiSha256=(Get-FileHash -LiteralPath build/diagnostic/DIAGNOSTIC.EFI -Algorithm SHA256).Hash
  BuiltUtc=[DateTime]::UtcNow.ToString('o');Sources=$sourceManifest
 } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath build/diagnostic/manifest.json -Encoding utf8
} finally {Pop-Location}
