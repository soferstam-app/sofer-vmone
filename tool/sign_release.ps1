# Signs a release APK with the new key and the rotation lineage, then verifies.
#
# Gradle cannot attach a signing certificate lineage, so the APK it produces is
# re-signed here. Without the lineage every existing user is stranded: Android
# sees a different certificate and refuses the update, and the only way out is
# uninstalling — which deletes their work.
#
# See docs/SIGNING.md. Nothing should be published that has not been through
# this script and printed a lineage line.

param(
    [string]$Apk = "build\app\outputs\flutter-apk\app-release.apk",
    [string]$Keystore = "C:\keys\sofer-release.jks",
    [string]$Alias = "sofer",
    [string]$Lineage = "C:\keys\lineage.bin"
)

$ErrorActionPreference = "Stop"

function Find-ApkSigner {
    $root = Join-Path $env:LOCALAPPDATA "Android\Sdk\build-tools"
    if (-not (Test-Path $root)) { throw "Android build-tools not found at $root" }
    # Newest build-tools wins; the tool is backwards compatible.
    $newest = Get-ChildItem $root -Directory | Sort-Object Name -Descending |
        Select-Object -First 1
    $signer = Join-Path $newest.FullName "apksigner.bat"
    if (-not (Test-Path $signer)) { throw "apksigner not found in $($newest.FullName)" }
    return $signer
}

foreach ($required in @($Apk, $Keystore, $Lineage)) {
    if (-not (Test-Path $required)) { throw "missing: $required" }
}

$signer = Find-ApkSigner
$signed = [System.IO.Path]::ChangeExtension($Apk, $null) + "signed.apk"

Write-Host "signing $Apk" -ForegroundColor Cyan
& $signer sign `
    --ks $Keystore --ks-key-alias $Alias `
    --lineage $Lineage `
    --out $signed `
    $Apk
if ($LASTEXITCODE -ne 0) { throw "signing failed" }

Write-Host "`nverifying" -ForegroundColor Cyan
$report = & $signer verify --print-certs -v $signed 2>&1
$report | Write-Host

# The two things that decide whether an existing user can install this at all.
if ($report -notmatch "Verified using v3 scheme.*true") {
    throw "no v3 signature — rotation is not in effect, do not publish"
}
if ($report -notmatch "(?i)lineage") {
    throw "no signing lineage — every existing install would be stranded"
}

Write-Host "`nOK: $signed" -ForegroundColor Green
Write-Host "Install it over 0.3.1 on a real device before publishing." -ForegroundColor Yellow
