param(
    [string] $ModelDirectory,
    [string] $Flutter = 'flutter',
    [string] $PdfiumArchive,
    [string] $OnnxNoticesDirectory,
    [switch] $ReleaseCandidate,
    [ValidatePattern('^r[1-9][0-9]*$')] [string] $Revision
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (!$ReleaseCandidate -and !$ModelDirectory) { throw 'ModelDirectory is required for a voice test build' }
if ($ReleaseCandidate -and $Revision) { throw 'Use Revision for test packages only' }
$model = if ($ModelDirectory) { (Resolve-Path -LiteralPath $ModelDirectory).Path }
if ($PdfiumArchive) { $PdfiumArchive = (Resolve-Path -LiteralPath $PdfiumArchive).Path }
$versionLine = Select-String -LiteralPath (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s+([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+\s*$'
if (!$versionLine) { throw 'App version not found in pubspec.yaml' }
$version = $versionLine.Matches[0].Groups[1].Value
$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$output = if ($ReleaseCandidate) {
    $edition = if ($model) { 'voice' } else { 'regular' }
    Join-Path $root "dist/$version-candidate/$edition"
} else {
    Join-Path $root "dist/$version-voice-model-test"
}
$stage = Join-Path $output "build-$stamp"
$pair = Join-Path $output $(if ($Revision) { $Revision } else { "pair-$stamp" })
if (Test-Path -LiteralPath $pair) { throw "Build pair already exists: $pair" }
$packages = Join-Path $stage 'packages-out'
$name = "sofer-vmone-$version"
if (!$ReleaseCandidate) { $name += '-voice-model-test' }
if ($Revision) { $name += "-$Revision" }
$suffix = if ($ReleaseCandidate -and $model) { '-voice' } else { '' }
$buildOptions = @('--release', '--no-pub')
if ($ReleaseCandidate) { $buildOptions += '--dart-define=SOFER_YIDDISH_PREVIEW=true' }
$checksums = @{
    'encoder.int8.onnx' = '6C6FEBCB74A09435315A1D872A6539F6E7FC2C333533F14C74EDC0E85C49FFCD'
    'decoder.int8.onnx' = 'FEB03E7C8AA761593A9284A6FA1E91259BE3702DE75F630062256C1A59C5A906'
    'joiner.int8.onnx' = '1D2C6D8E6DABC5EB52DE52E95718E9BDFBFFBFE7EAD3808FB5FFD74E83BD9CAE'
    'tokens.txt' = 'E4EBB5E72A6AEEF47437A55FA2308EBBEDB7C51C557DE7A89BF965C23EA9AF4A'
}
if ($model) {
    foreach ($file in $checksums.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $model $file)).Hash -ne $checksums[$file]) {
            throw "Unexpected model checksum for $file"
        }
    }
}

New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach ($folder in @('android', 'assets', 'docs/help', 'lib', 'packages', 'tool/voice_model', 'windows')) {
    & robocopy (Join-Path $root $folder) (Join-Path $stage $folder) /E /XD build .dart_tool .gradle .kotlin ephemeral /XF '*.jks' '*.keystore' key.properties /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw "Could not stage $folder" }
}
foreach ($file in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage
}
if ($model) {
    foreach ($file in $checksums.Keys) {
        Copy-Item -LiteralPath (Join-Path $model $file) -Destination (Join-Path $stage 'tool/voice_model/assets')
    }
    $onnxRuntime = 'https://raw.githubusercontent.com/microsoft/onnxruntime/v1.28.2'
    $notices = @{
        'LICENSE' = @{ Name = 'ONNXRuntime-LICENSE.txt'; Hash = '2F07C72751AED99790B8A4869CF2311DF85A860B22DED05FA22803587A48922C' }
        'ThirdPartyNotices.txt' = @{ Name = 'ONNXRuntime-ThirdPartyNotices.txt'; Hash = '0E07B95F3A8D6230037707C5C4A2B554D12C4CB67369669AC255635528FFCEE2' }
    }
    foreach ($license in $notices.Keys) {
        $notice = $notices[$license]
        $target = Join-Path $stage "tool/voice_model/assets/$($notice.Name)"
        if ($OnnxNoticesDirectory) {
            $source = Join-Path $OnnxNoticesDirectory $notice.Name
            Copy-Item -LiteralPath $source -Destination $target
        } else {
            Invoke-WebRequest "$onnxRuntime/$license" -OutFile $target
        }
        if ((Get-FileHash -LiteralPath $target).Hash -ne $notice.Hash) {
            throw "Unexpected ONNX Runtime notice checksum for $license"
        }
    }
    Set-Content -LiteralPath (Join-Path $stage 'pubspec_overrides.yaml') -Value @'
dependency_overrides:
  record_windows:
    path: packages/record_windows
  sofer_voice_model:
    path: tool/voice_model
'@ -Encoding utf8
}

Push-Location $stage
try {
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve package dependencies' }
    New-Item -ItemType Directory -Path $packages | Out-Null
    & $Flutter build apk @buildOptions
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed' }
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination (Join-Path $packages "$name-android$suffix.apk")

    $bundle = Join-Path $stage 'build/windows/x64/runner/Release'
    if ($PdfiumArchive) {
        $cmakeBuild = Join-Path $stage 'build/windows/x64'
        New-Item -ItemType Directory -Path $cmakeBuild -Force | Out-Null
        $cache = @(
            "STAMSOFER_PDFIUM_ARCHIVE:FILEPATH=$($PdfiumArchive.Replace('\', '/'))",
            "CMAKE_INSTALL_PREFIX:PATH=$($bundle.Replace('\', '/'))"
        )
        [IO.File]::WriteAllLines((Join-Path $cmakeBuild 'CMakeCache.txt'), $cache, [Text.UTF8Encoding]::new($false))
    }
    & $Flutter build windows @buildOptions
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath (Join-Path $packages "$name-windows$suffix.zip")

    Get-ChildItem -LiteralPath $packages -File | Sort-Object Name | ForEach-Object {
        "$((Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant())  $($_.Name)"
    } | Set-Content -LiteralPath (Join-Path $packages 'SHA256SUMS.txt') -Encoding ascii
    # Rename in the same output tree only after both artifacts are ready.
    [IO.Directory]::Move($packages, $pair)
    Write-Output $pair
} finally {
    Pop-Location
}
