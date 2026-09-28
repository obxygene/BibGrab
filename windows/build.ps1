param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",
    [bool]$SelfContained = $true
)
$ErrorActionPreference = "Stop"
$deployment = if ($SelfContained) { "self-contained" } else { "framework-dependent" }
$outputPath = Join-Path $PSScriptRoot "../build/windows/$Runtime/$deployment"
$arguments = @(
    "publish", "$PSScriptRoot/BibGrab.Windows/BibGrab.Windows.csproj",
    "-c", "Release", "-r", $Runtime,
    "--self-contained", $SelfContained.ToString().ToLowerInvariant(),
    "-p:PublishSingleFile=true", "-p:DebugType=None", "-p:DebugSymbols=false",
    "-o", $outputPath
)
if ($SelfContained) { $arguments += "-p:IncludeNativeLibrariesForSelfExtract=true" }
& dotnet @arguments
if ($LASTEXITCODE -ne 0) { throw "Windows build failed." }
Write-Host "Built ($deployment): $outputPath/BibGrab.exe"
