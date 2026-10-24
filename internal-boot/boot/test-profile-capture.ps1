# GPL-2.0-only. Verify the actual UEFI translation unit uses its machine profile.
param([string]$Clang='clang')
$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    $output = 'build/profile-capture'
    [void][IO.Directory]::CreateDirectory((Join-Path $PWD $output))
    $common = @('-target','x86_64-pc-windows-msvc','-std=c11','-ffreestanding',
        '-fno-builtin','-fno-stack-protector','-mno-red-zone','-fshort-wchar',
        '-Os','-Wall','-Wextra','-Werror','-DGU_FULL_UNLOCK',
        '-I','../../deps/edk2/MdePkg/Include',
        '-I','../../deps/edk2/MdePkg/Include/X64','-c','diagnostic.c')
    & $Clang @common '-DGU_PROFILE_Z690_3060TI' '-o' "$output/z690.obj"
    if ($LASTEXITCODE -ne 0) { throw 'Z690 capture compile failed.' }
    & $Clang @common '-DGU_PROFILE_B650M_3090FE' '-o' "$output/nonaggregate.obj"
    if ($LASTEXITCODE -ne 0) { throw 'Nonaggregate control compile failed.' }
    $z690 = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes(
        (Join-Path $PSScriptRoot "$output/z690.obj")))
    $control = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes(
        (Join-Path $PSScriptRoot "$output/nonaggregate.obj")))
    if ($z690.Contains('gop-info') -or -not $control.Contains('gop-info')) {
        throw 'Compiled capture profile did not accept only the aggregate GOP.'
    }
    Write-Output 'PASS Z690 compiled capture accepts aggregate GOP; nonaggregate control rejects it.'
} finally {
    Pop-Location
}
