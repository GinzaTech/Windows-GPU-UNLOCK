# GPL-2.0-only. Windows entry point for the one verified RTX 3060 Ti profile.
# Plan is read-only. Build writes local ignored output. Install stages an F8 entry.
[CmdletBinding()]
param(
 [switch]$Plan,
 [switch]$BuildOnly,
 [switch]$Install,
 [switch]$RecoverWindowsFirst,
 [ValidatePattern('^[D-Zd-z]$')][string]$UnlockDriveLetter,
 [string]$AssetsDirectory,
 [string]$Clang='clang',
 [string]$LldLink='lld-link',
 [string]$Python='python'
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$headless=Join-Path $repo 'internal-boot/Headless.ps1'
$profile='ASUS-TUF-GAMING-Z690-PLUS-WIFI-D4-2602-RTX3060TI'
$espType='{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'

if(@(@($Plan,$BuildOnly,$Install,$RecoverWindowsFirst) | Where-Object {$_}).Count -gt 1){throw 'Choose one mode: -Plan, -BuildOnly, -Install, or -RecoverWindowsFirst'}
if($AssetsDirectory -and !$Install){throw '-AssetsDirectory is only used with -Install'}
if($Install -and !$AssetsDirectory){throw '-Install requires -AssetsDirectory'}
if(($BuildOnly -or $Install) -and !$UnlockDriveLetter){throw 'Specify the existing, separate EFI partition with -UnlockDriveLetter'}

function Assert-Administrator {
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=[Security.Principal.WindowsPrincipal]::new($identity)
 if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  throw 'Open PowerShell as Administrator for this mode'
 }
}
function Resolve-BuildTool([string]$Name){
 $command=Get-Command -Name $Name -CommandType Application -ErrorAction Stop | Select-Object -First 1
 if(!$command -or !$command.Source){throw ('Build tool unavailable: '+$Name)}
 return $command.Source
}
function Get-LocalPlan {
 $reasons=[Collections.Generic.List[string]]::new()
 $board=$null;$bios=$null;$gpus=@();$windowsEsp=$null;$unlockEsp=$null
 $secureBoot=$null;$bitLocker=$null;$os=$null
 try{$os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop}catch{$reasons.Add('Could not read Windows OS identity')}
 if(!$os){$reasons.Add('Windows OS identity is unavailable')}
 elseif($os.OSArchitecture -notmatch '64'){$reasons.Add('A 64-bit Windows installation is required')}
 try{$board=Get-CimInstance Win32_BaseBoard -ErrorAction Stop;$bios=Get-CimInstance Win32_BIOS -ErrorAction Stop}catch{$reasons.Add('Could not read motherboard and BIOS identity')}
 if(!$board -or !$bios){$reasons.Add('Motherboard or BIOS identity is unavailable')}
 if($board -and $bios -and ($board.Product -ne 'TUF GAMING Z690-PLUS WIFI D4' -or $bios.SMBIOSBIOSVersion -ne '2602')){
  $reasons.Add('No verified unlock profile for this motherboard/BIOS')
 }
 try{$gpus=@(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object {$_.PNPDeviceID -match '^PCI\\VEN_10DE&DEV_2489&SUBSYS_88271043(?:&|\\)'})}catch{$reasons.Add('Could not read PCI GPU identity')}
 if($gpus.Count -ne 1 -or $gpus[0].Status -ne 'OK'){$reasons.Add('Expected exactly one working RTX 3060 Ti PCI 10DE:2489 / 1043:8827')}
 try{
  $secureBootValue=Confirm-SecureBootUEFI -ErrorAction Stop
  if($null -eq $secureBootValue){throw 'No Secure Boot state returned'}
  $secureBoot=[bool]$secureBootValue
 }catch{$reasons.Add('Cannot establish UEFI Secure Boot state')}
 if($secureBoot -eq $true){$reasons.Add('Secure Boot must be disabled for the unsigned experimental EFI')}
 try{$bitLocker=@(Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop)}catch{$reasons.Add('Cannot establish BitLocker state for C:')}
 if($null -eq $bitLocker -or $bitLocker.Count -ne 1 -or $null -eq $bitLocker[0].VolumeStatus -or $null -eq $bitLocker[0].ProtectionStatus){
  $reasons.Add('BitLocker state for C: is missing or ambiguous')
 }elseif([int]$bitLocker[0].VolumeStatus -ne 0 -or [int]$bitLocker[0].ProtectionStatus -ne 0){
  $reasons.Add('C: must be fully decrypted with BitLocker protection off')
 }
 try {
  $systemEsp=@(Get-Partition -ErrorAction Stop | Where-Object {$_.IsSystem -and $_.GptType -eq $espType -and $_.Guid})
  if($systemEsp.Count -ne 1){throw 'Expected one system EFI partition'}
  $windowsEsp=$systemEsp[0]
  $v=$windowsEsp | Get-Volume -ErrorAction Stop
  if(!$v.Path -or !(Test-Path -LiteralPath (Join-Path $v.Path 'EFI/Microsoft/Boot/bootmgfw.efi'))){throw 'Windows Boot Manager file is unavailable'}
 }catch{$reasons.Add('Could not verify the unique Windows EFI partition: '+$_.Exception.Message)}
 if(!$UnlockDriveLetter){$reasons.Add('Select the existing dedicated EFI partition with -UnlockDriveLetter')}
 if($UnlockDriveLetter){
  try {
   $unlockEsp=Get-Partition -DriveLetter $UnlockDriveLetter -ErrorAction Stop
   $v=$unlockEsp | Get-Volume -ErrorAction Stop
   if($unlockEsp.IsSystem -or $unlockEsp.GptType -ne $espType -or $unlockEsp.Size -lt 1GB -or $v.FileSystem -ne 'FAT32' -or !$v.Path -or !$unlockEsp.Guid){throw 'Use an existing, separate FAT32 EFI partition of at least 1 GiB'}
   if($windowsEsp -and $unlockEsp.Guid -eq $windowsEsp.Guid){throw 'The selected partition is the Windows EFI partition'}
  }catch{$unlockEsp=$null;$reasons.Add('Could not verify the dedicated unlock EFI partition: '+$_.Exception.Message)}
 }
 return [pscustomobject]@{
  HardwareProfile=$profile
  Board=$(if($board){[string]$board.Product}else{$null})
  Bios=$(if($bios){[string]$bios.SMBIOSBIOSVersion}else{$null})
  GpuPnpId=$(if($gpus.Count -eq 1){[string]$gpus[0].PNPDeviceID}else{$null})
  WindowsEspGuid=$(if($windowsEsp){[string]$windowsEsp.Guid}else{$null})
  UnlockEspGuid=$(if($unlockEsp){[string]$unlockEsp.Guid}else{$null})
  SecureBoot=$secureBoot
  BitLockerVolumeStatus=$(if($bitLocker.Count -eq 1){[string]$bitLocker[0].VolumeStatus}else{$null})
  BitLockerProtectionStatus=$(if($bitLocker.Count -eq 1){[string]$bitLocker[0].ProtectionStatus}else{$null})
  Supported=($reasons.Count -eq 0)
  Reasons=@($reasons)
 }
}
function Assert-ExistingConfiguration($plan){
 $configPath=Join-Path $repo 'internal-boot/local-config.json'
 $headerPath=Join-Path $repo 'internal-boot/boot/platform-config.h'
 if((Test-Path -LiteralPath $configPath) -xor (Test-Path -LiteralPath $headerPath)){
  throw 'Incomplete local partition configuration; inspect it before rebuilding'
 }
 if(!(Test-Path -LiteralPath $configPath)){
  & (Join-Path $repo 'internal-boot/Configure.ps1') -UnlockDriveLetter $UnlockDriveLetter -WindowsEspGuid ([guid]$plan.WindowsEspGuid) -HardwareProfile z690-3060ti
  if(!$?){throw 'Local configuration failed'}
 }else{
  . (Join-Path $repo 'internal-boot/install/headless-package.ps1')
  $cfg=Assert-HeadlessLocalConfig $repo
  if($cfg.UnlockDriveLetter -ne $UnlockDriveLetter.ToUpperInvariant() -or $cfg.UnlockPartitionGuid -ne $plan.UnlockEspGuid -or $cfg.WindowsPartitionGuid -ne $plan.WindowsEspGuid){
   throw 'Existing local configuration belongs to another EFI partition; preserve and inspect it before rebuilding'
  }
 }
}
function Assert-Assets([string]$Directory){
 . (Join-Path $repo 'internal-boot/install/headless-package.ps1')
 $assets=[IO.Path]::GetFullPath($Directory)
 if(!(Test-Path -LiteralPath $assets -PathType Container)){throw 'Firmware assets directory is unavailable'}
 foreach($item in @(Get-HeadlessAssetSpecs $repo)){
  $file=Join-Path $assets $item.Name
  if(!(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -ne $item.Bytes -or (Get-FileHash -LiteralPath $file).Hash -ne $item.Sha256){
   throw ('Firmware asset missing or mismatched: '+$item.Name)
  }
 }
 return $assets
}
function Read-Bcd([string[]]$Arguments){
 $output=@(& bcdedit @Arguments)
 if($LASTEXITCODE -ne 0){throw ('BCDEdit could not read '+($Arguments -join ' '))}
 return ($output -join "`n")
}
function Assert-ExistingF8Entry($state,$plan){
 $fw=Read-Bcd @('/enum','{fwbootmgr}')
 if($fw -match '(?mi)^bootsequence\s+') {throw 'Pending BootNext; Windows-first state cannot be verified'}
 $match=[regex]::Match($fw,'(?ms)^displayorder\s+(.*?)(?=\r?\n\S|\z)')
 if(!$match.Success){throw 'Firmware boot order is unavailable'}
 $order=@([regex]::Matches($match.Groups[1].Value,'\{(?:bootmgr|[0-9a-f-]{36})\}') | ForEach-Object {$_.Value})
 if($order.Count -lt 2 -or $order[0] -ne '{bootmgr}' -or @($order | Where-Object {$_ -eq $state.EntryId}).Count -ne 1 -or @($order | Select-Object -Unique).Count -ne $order.Count){
  throw 'Windows Boot Manager is not first or the expected F8 entry is missing/duplicated'
 }
 $entry=Read-Bcd @('/enum',[string]$state.EntryId)
 if($entry -notmatch '(?mi)^path\s+\\EFI\\WindowsGPUUnlock\\HEADLESS\.EFI\s*$' -or
    $entry -notmatch '(?m)^description\s+GPU Headless UNLOCK - EXPERIMENTAL\s*$'){
  throw 'Existing firmware entry path or description changed'
 }
 $device=[regex]::Match($entry,'(?mi)^device\s+partition=(\S+)\s*$')
 if(!$device.Success){throw 'Existing firmware entry partition is unavailable'}
 $target=[string]$device.Groups[1].Value
 if($target -ieq ($UnlockDriveLetter.ToUpperInvariant()+':')){return}
 $partition=Get-Partition -DriveLetter $UnlockDriveLetter
 if($partition.Guid -ne $plan.UnlockEspGuid){throw 'Dedicated EFI partition changed'}
 $paths=@($partition.AccessPaths | Where-Object {$_ -match '^\\\\\?\\Volume\{[0-9a-f-]{36}\}\\$'})
 if($paths.Count -eq 1 -and ($target -ieq $paths[0] -or $target -ieq $paths[0].TrimEnd([char]92))){return}
 if($target -notmatch '^\\Device\\HarddiskVolume[0-9]+$'){throw 'F8 entry points to another partition'}
 $rows=@(& fltmc.exe volumes 2>&1)
 if($LASTEXITCODE -ne 0){throw 'Cannot resolve the dedicated EFI partition device'}
 $found=@($rows | ForEach-Object {
  $m=[regex]::Match($_,('(?i)^\s*'+[regex]::Escape($UnlockDriveLetter.ToUpperInvariant()+':')+'\s+(\\Device\\HarddiskVolume[0-9]+)(?:\s|$)'))
  if($m.Success){$m.Groups[1].Value}
 })
 if($found.Count -ne 1 -or $target -ine $found[0]){throw 'F8 entry device differs from the dedicated EFI partition'}
}

if($RecoverWindowsFirst){
 Assert-Administrator
 & $headless -RestoreWindowsFirst
 if(!$?){throw 'Windows-first recovery failed'}
 return
}
$localPlan=Get-LocalPlan
if(!$BuildOnly -and !$Install){$localPlan;return}
Assert-Administrator
if(!$localPlan.Supported){throw ('Machine is not ready for the verified RTX 3060 Ti profile: '+($localPlan.Reasons -join '; '))}
$clangPath=Resolve-BuildTool $Clang
$lldPath=Resolve-BuildTool $LldLink
$pythonPath=Resolve-BuildTool $Python
$assets=$null
if($Install){$assets=Assert-Assets $AssetsDirectory}
Assert-ExistingConfiguration $localPlan
& (Join-Path $repo 'research/headless/build-unlock.ps1') -HardwareProfile z690-3060ti -Clang $clangPath -LldLink $lldPath -Python $pythonPath
if(!$?){throw 'Headless build failed'}
. (Join-Path $repo 'internal-boot/install/headless-package.ps1')
$package=Assert-HeadlessPackage $repo
if($package.HardwareProfile -ne $profile){throw 'Built package uses a different hardware profile'}
if($BuildOnly){
 Write-Output ([pscustomobject]@{Mode='BuiltOnly';HardwareProfile=$package.HardwareProfile;WrapperSha256=$package.EfiSha256;ChildSha256=$package.ChildSha256;Installed=$false})
 return
}
$statePath=Join-Path $repo 'internal-boot/install/headless-state.json'
if(Test-Path -LiteralPath $statePath){
 $state=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
 if($state.Mode -notin @('registered','windows-first') -or $state.EfiSha256 -ne $package.EfiSha256 -or $state.ChildSha256 -ne $package.ChildSha256 -or $state.EntryId -notmatch '^\{[0-9a-f-]{36}\}$'){
  throw 'An existing registration uses another package or mode; inspect it before changing boot files'
 }
 Assert-ExistingF8Entry $state $localPlan
 & $headless -Assets $assets
 if(!$?){throw 'Installed package verification failed'}
 Assert-ExistingF8Entry $state $localPlan
 Write-Output 'Existing identical F8 package verified. Windows Boot Manager order unchanged.'
}else{
 & $headless -Assets $assets -Register
 if(!$?){throw 'F8 registration failed'}
}
