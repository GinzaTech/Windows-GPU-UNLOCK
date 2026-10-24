# CUDA 12.6 runtime and cuBLAS redist only; pinned to NVIDIA's redistrib_12.6.0.json.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$downloads=Join-Path $root 'downloads'
$packages=Join-Path $root 'packages/rtx3060ti'
New-Item -ItemType Directory -Path $downloads,$packages -Force | Out-Null
$items=@(
 @{Name='cuda_cudart';File='cuda_cudart-windows-x86_64-12.6.37-archive.zip';Path='cuda_cudart/windows-x86_64/cuda_cudart-windows-x86_64-12.6.37-archive.zip';Bytes=2512085;Hash='c66badb16921c4acb7abc38f211d530c2f290bd52c2cbdb5fb12095dc6eab0a9'},
 @{Name='libcublas';File='libcublas-windows-x86_64-12.6.0.22-archive.zip';Path='libcublas/windows-x86_64/libcublas-windows-x86_64-12.6.0.22-archive.zip';Bytes=404037803;Hash='4f38ba0ab036296bcc48727cc3ed27e633911c0fc5dccb60d5131657b1a58002'}
)
$receipt=@()
foreach($item in $items){
 $zip=Join-Path $downloads $item.File
 if(!(Test-Path -LiteralPath $zip)){
  Invoke-WebRequest -Uri ('https://developer.download.nvidia.com/compute/cuda/redist/'+$item.Path) -OutFile $zip
 }
 $file=Get-Item -LiteralPath $zip
 $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
 if($file.Length -ne $item.Bytes -or $hash -ne $item.Hash){throw ('CUDA package pin mismatch: '+$item.Name)}
 $dest=Join-Path $packages $item.Name
 if(!(Test-Path -LiteralPath $dest)){Expand-Archive -LiteralPath $zip -DestinationPath $dest}
 $receipt+=[ordered]@{Name=$item.Name;Version=$(if($item.Name -eq 'cuda_cudart'){'12.6.37'}else{'12.6.0.22'});URL=('https://developer.download.nvidia.com/compute/cuda/redist/'+$item.Path);Bytes=$item.Bytes;SHA256=$item.Hash}
}
$receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'packages-manifest.json') -Encoding utf8
Write-Output 'CUDA runtime and cuBLAS archives verified; no driver or GPU setting changed.'
