param(
  [Parameter(Mandatory = $true)] [string] $Bundle,
  [int] $Bytes = 2621440
)

$target = Join-Path $Bundle '.release\size-adjustment.bin'
New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
$buffer = New-Object byte[] $Bytes
[System.Security.Cryptography.RandomNumberGenerator]::Fill($buffer)
[System.IO.File]::WriteAllBytes($target, $buffer)
