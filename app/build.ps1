# Build the control app's APK without Gradle.
#
# Gradle plus the Android Gradle Plugin is roughly 500 MB of downloads and a first build that
# spends minutes resolving dependencies. This app is one activity with no library dependencies,
# so the toolchain underneath AGP can be driven directly:
#
#   aapt2 compile   resources -> flat files
#   aapt2 link      flat files + manifest + android.jar -> an APK with resources and R.java
#   javac           sources -> .class, against android.jar
#   d8              .class -> classes.dex
#   zip             classes.dex into the APK
#   zipalign        required before signing
#   apksigner       sign with a debug key
#
# **aapt2, d8 and apksigner all fail in confusing ways when given the wrong thing**, so every
# step here checks its input exists first and reports which one is missing.

[CmdletBinding()]
param(
    [string]$Sdk   = "D:\TG_Bot\_android_tools\sdk",
    [string]$AppDir = "",
    [switch]$Clean,
    [switch]$Install
)

$ErrorActionPreference = "Stop"

# Resolved in the body, not as a parameter default: `$PSScriptRoot` is not populated when the
# default is evaluated, so using it there passes an empty string and every later Join-Path fails
# with "Cannot bind argument to parameter 'Path' because it is an empty string".
if (-not $AppDir) {
    if ($PSScriptRoot) { $AppDir = $PSScriptRoot }
    elseif ($PSCommandPath) { $AppDir = Split-Path $PSCommandPath -Parent }
    else { $AppDir = (Get-Location).Path }
}
$AppDir = (Resolve-Path $AppDir).Path

# --------------------------------------------------------------------------- paths

$BuildTools = Join-Path $Sdk "build-tools\34.0.0"
$Platform   = Join-Path $Sdk "platforms\android-34"
$AndroidJar = Join-Path $Platform "android.jar"
$Adb        = Join-Path $Sdk "platform-tools\adb.exe"

$Aapt2      = Join-Path $BuildTools "aapt2.exe"
$D8         = Join-Path $BuildTools "d8.bat"
$ZipAlign   = Join-Path $BuildTools "zipalign.exe"
$ApkSigner  = Join-Path $BuildTools "apksigner.bat"

$Manifest   = Join-Path $AppDir "AndroidManifest.xml"
$ResDir     = Join-Path $AppDir "res"
$SrcDir     = Join-Path $AppDir "src"
$OutDir     = Join-Path $AppDir "build"
$Keystore   = Join-Path $AppDir "debug.keystore"

$CompiledRes = Join-Path $OutDir "res-compiled.zip"
$LinkedApk   = Join-Path $OutDir "app-unsigned-aligned.apk"
$UnsignedApk = Join-Path $OutDir "app-unsigned.apk"
$ClassesDir  = Join-Path $OutDir "classes"
$DexDir      = Join-Path $OutDir "dex"
$FinalApk    = Join-Path $OutDir "bot-panel.apk"

function Step($text) { Write-Host ""; Write-Host "==> $text" -ForegroundColor Cyan }
function Ok($text)   { Write-Host "    $([char]0x2713) $text" -ForegroundColor Green }
function Bad($text)  { Write-Host "    $([char]0x2717) $text" -ForegroundColor Red }
function Info($text) { Write-Host "    $([char]0x00B7) $text" -ForegroundColor DarkGray }

# --------------------------------------------------------------------------- checks

Step "Checking the toolchain"
$missing = @()
foreach ($tool in @($Aapt2, $D8, $ZipAlign, $ApkSigner, $AndroidJar, $Manifest)) {
    if (-not (Test-Path $tool)) { $missing += $tool }
}
if ($missing.Count -gt 0) {
    foreach ($m in $missing) { Bad "missing: $m" }
    Write-Host ""
    Write-Host "  Install the SDK components with:" -ForegroundColor Yellow
    Write-Host "    sdkmanager `"platform-tools`" `"platforms;android-34`" `"build-tools;34.0.0`""
    exit 1
}
Ok "aapt2, d8, zipalign, apksigner, android.jar and the manifest are all present"

$javaHome = $env:JAVA_HOME
if (-not $javaHome) {
    $javac = Get-Command javac -ErrorAction SilentlyContinue
    if ($javac) { $javaHome = Split-Path (Split-Path $javac.Source -Parent) -Parent }
}
if (-not $javaHome) { Bad "JAVA_HOME is not set and javac is not on PATH"; exit 1 }
Ok "java home: $javaHome"

if ($Clean -and (Test-Path $OutDir)) {
    Remove-Item $OutDir -Recurse -Force
    Info "cleaned $OutDir"
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# --------------------------------------------------------------------------- resources

Step "Compiling resources (aapt2 compile)"
# `--dir` takes the whole res tree and writes a zip of flat files, which is what link wants.
& $Aapt2 compile --dir $ResDir -o $CompiledRes
if ($LASTEXITCODE -ne 0) { Bad "aapt2 compile failed with $LASTEXITCODE"; exit 1 }
Ok "resources compiled"

# --------------------------------------------------------------------------- link

Step "Linking (aapt2 link)"
# --min-sdk-version / --target-sdk-version are passed explicitly: without them aapt2 uses the
# oldest it supports, which makes Android apply legacy behaviour to a modern app.
& $Aapt2 link `
    -o $UnsignedApk `
    -I $AndroidJar `
    --manifest $Manifest `
    --min-sdk-version 24 `
    --target-sdk-version 34 `
    --version-code 1 `
    --version-name "1.0" `
    $CompiledRes
if ($LASTEXITCODE -ne 0) { Bad "aapt2 link failed with $LASTEXITCODE"; exit 1 }
Ok "linked: $(Split-Path $UnsignedApk -Leaf)"

# --------------------------------------------------------------------------- java

Step "Compiling Java (javac)"
if (Test-Path $ClassesDir) { Remove-Item $ClassesDir -Recurse -Force }
New-Item -ItemType Directory -Path $ClassesDir -Force | Out-Null

$sources = Get-ChildItem -Path $SrcDir -Recurse -Filter *.java | ForEach-Object { $_.FullName }
if ($sources.Count -eq 0) { Bad "no .java files under $SrcDir"; exit 1 }
Info "$($sources.Count) source file(s)"

# --release 8 rather than -source/-target: it also pins the bootclasspath, and without that
# javac happily compiles against JDK 21 APIs that do not exist on Android.
& javac `
    --release 8 `
    -encoding UTF-8 `
    -classpath $AndroidJar `
    -d $ClassesDir `
    $sources
if ($LASTEXITCODE -ne 0) { Bad "javac failed with $LASTEXITCODE"; exit 1 }
Ok "compiled $(($sources).Count) file(s)"

# --------------------------------------------------------------------------- dex

Step "Dexing (d8)"
if (Test-Path $DexDir) { Remove-Item $DexDir -Recurse -Force }
New-Item -ItemType Directory -Path $DexDir -Force | Out-Null

$classes = Get-ChildItem -Path $ClassesDir -Recurse -Filter *.class | ForEach-Object { $_.FullName }
if ($classes.Count -eq 0) { Bad "javac produced no .class files"; exit 1 }
Info "$($classes.Count) class file(s)"

# --lib android.jar gives d8 the platform APIs to resolve against; without it every framework
# call is reported as a missing class and the dex step fails.
& $D8 --lib $AndroidJar --min-api 24 --output $DexDir $classes
if ($LASTEXITCODE -ne 0) { Bad "d8 failed with $LASTEXITCODE"; exit 1 }
$dexFile = Join-Path $DexDir "classes.dex"
if (-not (Test-Path $dexFile)) { Bad "d8 produced no classes.dex"; exit 1 }
Ok "classes.dex  $([int]((Get-Item $dexFile).Length/1KB)) KB"

# --------------------------------------------------------------------------- package

Step "Packaging (classes.dex into the APK)"
# .NET's ZipArchive is used rather than Compress-Archive: the latter writes a zip whose entries
# carry a path prefix, and an APK needs classes.dex at its root.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::Open($UnsignedApk, [System.IO.Compression.ZipArchiveMode]::Update)
try {
    $existing = $zip.Entries | Where-Object { $_.FullName -eq "classes.dex" }
    foreach ($entry in $existing) { $entry.Delete() }
    # CompressionLevel.NoCompression: a dex is already compact, and the platform maps it directly
    # from the APK, which a deflated entry would prevent.
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zip, $dexFile, "classes.dex", [System.IO.Compression.CompressionLevel]::NoCompression) | Out-Null
} finally {
    $zip.Dispose()
}
Ok "classes.dex added"

# --------------------------------------------------------------------------- align + sign

Step "Aligning (zipalign)"
if (Test-Path $LinkedApk) { Remove-Item $LinkedApk -Force }
& $ZipAlign -f -p 4 $UnsignedApk $LinkedApk
if ($LASTEXITCODE -ne 0) { Bad "zipalign failed with $LASTEXITCODE"; exit 1 }
Ok "aligned to 4 bytes"

Step "Signing (apksigner)"
if (-not (Test-Path $Keystore)) {
    Info "no keystore; generating a debug one"
    # A debug key is enough for sideloading. Its password is public by convention, which is
    # exactly why it must not be used for anything distributed.
    #
    # **Run through cmd, not called directly.** With `$ErrorActionPreference = "Stop"`,
    # PowerShell turns a native command's stderr into a terminating error - and keytool writes
    # its progress there ("Generating 2,048 bit RSA key pair...") , so a successful key generation
    # aborted the whole build. cmd sees the same text as ordinary output and passes it through.
    $keytoolCmd = "keytool -genkeypair -v -keystore `"$Keystore`" -storepass android -keypass android " +
                  "-alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 " +
                  "-dname `"CN=Android Debug,O=Android,C=US`""
    cmd /c "$keytoolCmd 2>&1" | Out-Null
    if (-not (Test-Path $Keystore)) { Bad "keytool did not create $Keystore"; exit 1 }
    Ok "debug keystore created"
} else {
    Info "using the existing debug keystore"
}

if (Test-Path $FinalApk) { Remove-Item $FinalApk -Force }
# Same reasoning as keytool: apksigner is chatty on stderr and is invoked through cmd so that
# chatter cannot abort the build.
#
# **The full path is required.** `cmd /c apksigner ...` fails with "'apksigner' is not recognized"
# because the SDK's build-tools directory is not on PATH - calling the .bat through PowerShell
# worked, but going through cmd does not inherit the same resolution.
$signCmd = "`"$ApkSigner`" sign --ks `"$Keystore`" --ks-pass pass:android --key-pass pass:android " +
           "--ks-key-alias androiddebugkey --out `"$FinalApk`" `"$LinkedApk`""
cmd /c "$signCmd 2>&1" | ForEach-Object { if ($_ -match '\S') { Info $_ } }
if (-not (Test-Path $FinalApk)) { Bad "apksigner produced no output"; exit 1 }

Step "Verifying the signature"
$verifyCmd = "`"$ApkSigner`" verify --print-certs `"$FinalApk`""
$verifyOut = cmd /c "$verifyCmd 2>&1"
$verifyCode = $LASTEXITCODE
$verifyOut | Select-Object -First 4 | ForEach-Object { Info $_ }
if ($verifyCode -ne 0) { Bad "the signature does not verify"; exit 1 }
Ok "signature verifies"

# --------------------------------------------------------------------------- done

$size = [int]((Get-Item $FinalApk).Length / 1KB)
Write-Host ""
Write-Host "  APK: $FinalApk  ($size KB)" -ForegroundColor Green

if ($Install) {
    Step "Installing on the device"
    & $Adb install -r $FinalApk
    if ($LASTEXITCODE -ne 0) { Bad "adb install failed"; exit 1 }
    Ok "installed"
}

Write-Host ""
Write-Host "  Install with:" -ForegroundColor DarkGray
Write-Host "    & `"$Adb`" install -r `"$FinalApk`"" -ForegroundColor DarkGray
Write-Host "  Or re-run this script with -Install" -ForegroundColor DarkGray
Write-Host ""
