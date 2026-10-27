Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $projectRoot 'build/windows/x64'
$cachePath = Join-Path $buildRoot 'CMakeCache.txt'
if (-not (Test-Path -LiteralPath $cachePath)) {
    throw 'Build the Windows release before running native sizing tests.'
}
$entry = Get-Content -LiteralPath $cachePath |
    Select-String '^CMAKE_COMMAND:INTERNAL='
$cmakePath = $entry.Line.Split('=', 2)[1]
& $cmakePath -S (Join-Path $projectRoot 'windows') -B $buildRoot
if ($LASTEXITCODE -ne 0) { throw 'Native test configuration failed.' }
& $cmakePath --build $buildRoot --config Release --target window_size_integration_test
if ($LASTEXITCODE -ne 0) { throw 'Native test build failed.' }

$previousSearchPath = $env:PATH
try {
    $env:PATH = "$(Join-Path $buildRoot 'runner/Release');$env:PATH"
    & (Join-Path $buildRoot 'tests/Release/window_size_integration_test.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Native window sizing checks failed.' }
} finally {
    $env:PATH = $previousSearchPath
}
