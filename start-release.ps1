$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$buildFile = Join-Path $PSScriptRoot 'build\web\main.dart.js'
$sourceFiles = @(Get-ChildItem -Path 'lib','assets','web' -Recurse -File)
$sourceFiles += Get-Item 'pubspec.yaml','pubspec.lock'
$newestSource = ($sourceFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
if (!(Test-Path -LiteralPath $buildFile) -or (Get-Item -LiteralPath $buildFile).LastWriteTimeUtc -lt $newestSource) {
  $localFlutter = Join-Path $PSScriptRoot '..\.tools\flutter\bin\flutter.bat'
  $flutter = if (Test-Path -LiteralPath $localFlutter) { $localFlutter } else { (Get-Command flutter -ErrorAction Stop).Source }
  & $flutter --no-version-check pub get
  if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency installation failed.' }
  & $flutter --no-version-check build web --release --no-pub
  if ($LASTEXITCODE -ne 0) { throw 'Flutter release build failed.' }
}
& node (Join-Path $PSScriptRoot 'tools\serve-preview.mjs')
if ($LASTEXITCODE -ne 0) { throw 'The release preview could not start.' }
