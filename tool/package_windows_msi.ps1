param(
  [Parameter(Mandatory = $true)][string]$SourceDir,
  [Parameter(Mandatory = $true)][string]$Output,
  [Parameter(Mandatory = $true)][string]$Version
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path (Join-Path $SourceDir 'twitch_freedom_ultra.exe'))) {
  throw "Release executable missing from $SourceDir"
}

$heat = Get-Command heat.exe -ErrorAction SilentlyContinue
$candle = Get-Command candle.exe -ErrorAction SilentlyContinue
$light = Get-Command light.exe -ErrorAction SilentlyContinue
if (-not $heat -or -not $candle -or -not $light) {
  throw 'WiX Toolset 3 is required to build the MSI installer.'
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) "twitch-freedom-msi-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $harvest = Join-Path $work 'harvest.wxs'
  $product = Join-Path $work 'product.wxs'
  $source = (Resolve-Path $SourceDir).Path

  & $heat.Source dir $source -nologo -gg -sfrag -srd -sreg `
    -dr INSTALLFOLDER -cg AppFiles -var var.SourceDir -out $harvest
  if ($LASTEXITCODE -ne 0) { throw 'WiX heat failed.' }

  @"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="Twitch Freedom" Language="1033" Version="$Version"
           Manufacturer="ornab74" UpgradeCode="9B6F65D8-4779-4DFB-BF3B-C34B06C9C16B">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine"
             Platform="x64" Description="Twitch Freedom desktop client" />
    <MajorUpgrade DowngradeErrorMessage="A newer Twitch Freedom version is already installed." />
    <MediaTemplate EmbedCab="yes" />
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="Twitch Freedom" />
      </Directory>
      <Directory Id="ProgramMenuFolder">
        <Directory Id="ApplicationProgramsFolder" Name="Twitch Freedom" />
      </Directory>
    </Directory>
    <DirectoryRef Id="ApplicationProgramsFolder">
      <Component Id="ApplicationShortcut" Guid="*" Win64="yes">
        <Shortcut Id="StartMenuShortcut" Name="Twitch Freedom"
                  Target="[INSTALLFOLDER]twitch_freedom_ultra.exe"
                  WorkingDirectory="INSTALLFOLDER" />
        <RemoveFolder Id="CleanApplicationProgramsFolder" On="uninstall" />
        <RegistryValue Root="HKLM" Key="Software\ornab74\TwitchFreedom"
                       Name="Installed" Type="integer" Value="1" KeyPath="yes" />
      </Component>
    </DirectoryRef>
    <Feature Id="Complete" Title="Twitch Freedom" Level="1">
      <ComponentGroupRef Id="AppFiles" />
      <ComponentRef Id="ApplicationShortcut" />
    </Feature>
  </Product>
</Wix>
"@ | Set-Content -Path $product -Encoding UTF8

  & $candle.Source -nologo -arch x64 "-dSourceDir=$source" `
    -out "$work\" $product $harvest
  if ($LASTEXITCODE -ne 0) { throw 'WiX candle failed.' }
  & $light.Source -nologo -spdb -out $Output `
    (Join-Path $work 'product.wixobj') (Join-Path $work 'harvest.wixobj')
  if ($LASTEXITCODE -ne 0) { throw 'WiX light failed.' }
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
