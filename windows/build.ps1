param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64"
)
$ErrorActionPreference = "Stop"
$outputPath = Join-Path $PSScriptRoot "../build/windows/$Runtime"
dotnet publish "$PSScriptRoot/BibGrab.Windows/BibGrab.Windows.csproj" `
    -c Release -r $Runtime --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None -p:DebugSymbols=false -o $outputPath
if ($LASTEXITCODE -ne 0) { throw "Windows build failed." }
Write-Host "Built: $outputPath/BibGrab.exe"
