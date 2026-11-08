param(
  [string]$SupabaseUrl = $env:SUPABASE_URL,
  [string]$SupabasePublishableKey = $env:SUPABASE_PUBLISHABLE_KEY
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$localFlutter = Join-Path $PSScriptRoot '..\.tools\flutter\bin\flutter.bat'
$flutter = if (Test-Path $localFlutter) { $localFlutter } else { (Get-Command flutter -ErrorAction Stop).Source }
if (!(Test-Path 'web/index.html')) {
  & $flutter --no-version-check create --empty --platforms=web --project-name pasyalph_supabase_flutter .
  if ($LASTEXITCODE -ne 0) { throw 'Flutter web setup failed.' }
}
& $flutter --no-version-check pub get
if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency installation failed.' }
$defines = @()
if ($SupabaseUrl) { $defines += "--dart-define=SUPABASE_URL=$SupabaseUrl" }
if ($SupabasePublishableKey) { $defines += "--dart-define=SUPABASE_PUBLISHABLE_KEY=$SupabasePublishableKey" }
& $flutter --no-version-check run --no-pub -d web-server --web-hostname 127.0.0.1 --web-port 3000 @defines
if ($LASTEXITCODE -ne 0) { throw 'Flutter web server failed.' }
