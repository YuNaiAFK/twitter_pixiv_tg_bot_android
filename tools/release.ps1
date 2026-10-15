<#
.SYNOPSIS
    Manage GitHub releases for this project - without the ability to destroy one.

.DESCRIPTION
    A release is a published artifact other people may have downloaded. Renaming or deleting one
    breaks links that were handed out and cannot be undone. This script therefore has **no code
    path that renames or deletes a release**, and its one destructive operation - replacing an
    uploaded asset, which GitHub does not allow any other way - needs an explicit flag.

    That is deliberate. The v1.0 release was destroyed once by a single PATCH that looked
    innocuous:

        PATCH /releases/{id}  {"tag_name": "v1.3"}

    GitHub accepts it, moves the release to the new tag and removes the old tag's release page.
    Nothing errors. A tool that cannot express that request cannot make that mistake.

.EXAMPLE
    ./release.ps1 -List
    ./release.ps1 -Verify
    ./release.ps1 -Create -Notes notes.md
    ./release.ps1 -Create -Draft

.NOTES
    The token is read from git's credential store, which is already what pushing uses, and is
    never printed or written to disk.
#>
[CmdletBinding()]
param(
    # Show every release on GitHub with its assets.
    [switch]$List,

    # Check that /releases/latest resolves to the newest version, and that each release has the
    # files it should. Read-only.
    [switch]$Verify,

    # Publish the version in VERSION.properties as a new release. Refuses if that version already
    # has a release, because publishing over one is how a release gets lost.
    [switch]$Create,

    # Create the release as a draft: hidden until published.
    [switch]$Draft,

    # Use an existing release's notes file instead of generating them.
    [string]$Notes = "",

    # **Replace** an already-uploaded asset on a release. The only destructive option here, and it
    # needs the release tag and the asset name spelled out.
    [string]$ReplaceAsset = "",
    [string]$OnRelease = ""
)

$ErrorActionPreference = "Stop"
$Repo = "YuNaiAFK/twitter_pixiv_tg_bot_android"
$ProjectDir = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $ProjectDir "VERSION.properties"))) {
    $ProjectDir = $PSScriptRoot
}
$VersionFile = Join-Path $ProjectDir "VERSION.properties"
$ApkDir = Join-Path $ProjectDir "apk"

function Step($t) { Write-Host ""; Write-Host "==> $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "    $([char]0x2713) $t" -ForegroundColor Green }
function Bad($t)  { Write-Host "    $([char]0x2717) $t" -ForegroundColor Red }
function Info($t) { Write-Host "    $([char]0x00B7) $t" -ForegroundColor DarkGray }
function Warn($t) { Write-Host "    ! $t" -ForegroundColor Yellow }

function Get-Token {
    # Read from the same store git pushes with. Never echoed, never cached to a file.
    $payload = "protocol=https`nhost=github.com`n`n"
    $lines = $payload | & git credential fill 2>&1
    $pass = ($lines | Select-String '^password=') -replace '^password=', ''
    if (-not $pass) { Bad "no GitHub credential in the store"; exit 1 }
    return $pass.Trim()
}

$Token = Get-Token
$Headers = @{ Authorization = "token $Token"; "User-Agent" = "botpanel-release"; Accept = "application/vnd.github+json" }

function Api {
    param([string]$Path, [string]$Method = "GET", $Body = $null)
    $uri = if ($Path -like "http*") { $Path } else { "https://api.github.com/repos/$Repo$Path" }
    $args = @{ Uri = $uri; Method = $Method; Headers = $Headers; TimeoutSec = 120 }
    if ($Body) {
        $args.Body = ($Body | ConvertTo-Json -Depth 6)
        $args.ContentType = "application/json"
    }
    $result = Invoke-RestMethod @args

    # **Unwrap, or every caller silently iterates one item.**
    #
    # Invoke-RestMethod writes a JSON array with -NoEnumerate, so `return $result` hands the whole
    # array back as a single object. `@(Api "/releases")` then has Count 1 whose only element is
    # the list, `foreach ($r in $rels)` runs once with $r being the array, and `$r.tag_name`
    # interpolates as "v1.3 v1.0" - which is exactly how the first version of -Verify reported
    # "refs/tags/v1.3 v1.0 is missing".
    #
    # Piping through ForEach-Object emits the elements individually, so callers get the array they
    # expect. A single JSON object passes through unchanged.
    return $result | ForEach-Object { $_ }
}

function Get-Version {
    $values = @{}
    foreach ($line in (Get-Content $VersionFile)) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#") -or -not $t.Contains("=")) { continue }
        $i = $t.IndexOf("=")
        $values[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
    }
    return $values
}

function Show-Releases {
    Step "Releases on $Repo"
    $rels = @(Api "/releases")
    if ($rels.Count -eq 0) { Info "none"; return $rels }
    foreach ($r in ($rels | Sort-Object published_at)) {
        $flags = @()
        if ($r.draft) { $flags += "DRAFT" }
        if ($r.prerelease) { $flags += "prerelease" }
        $tag = if ($flags.Count) { "$($r.tag_name)  [$($flags -join ', ')]" } else { $r.tag_name }
        Write-Host "  $tag  - $($r.name)"
        Info "published $($r.published_at)  id=$($r.id)"
        foreach ($a in ($r.assets | Sort-Object name)) {
            Info ("  {0,-22} {1,9} KB   downloads={2}" -f $a.name, [math]::Round($a.size / 1KB, 1), $a.download_count)
        }
    }
    return $rels
}

# --------------------------------------------------------------------------- list

if ($List -or (-not $Verify -and -not $Create -and -not $ReplaceAsset)) {
    $rels = Show-Releases
    $v = Get-Version
    Step "VERSION.properties says $($v['versionName']) (code $($v['versionCode']))"
    $match = $rels | Where-Object { $_.tag_name -eq "v$($v['versionName'])" }
    if ($match) { Ok "release 'v$($v['versionName'])' exists" }
    else { Warn "no release for v$($v['versionName']) yet - publish it with -Create" }
    Write-Host ""
    return
}

# --------------------------------------------------------------------------- verify

if ($Verify) {
    $v = Get-Version
    $want = "v$($v['versionName'])"
    Step "Verifying"

    $rels = @(Api "/releases")
    Ok "$($rels.Count) release(s): $(($rels | ForEach-Object { $_.tag_name }) -join ', ')"

    # Every release must still carry the files it was published with. A missing asset means
    # something was deleted, which is the failure this whole script exists to prevent.
    $expected = @("bot-panel.apk", "termux.apk", "termux-api.apk", "termux-boot.apk")
    $problem = $false
    foreach ($r in $rels) {
        $have = $r.assets | ForEach-Object { $_.name }
        $missing = $expected | Where-Object { $_ -notin $have }
        if ($missing.Count -gt 0) {
            Bad "$($r.tag_name) is missing: $($missing -join ', ')"
            $problem = $true
        } else {
            Ok "$($r.tag_name): all $($expected.Count) assets present"
        }
        # An APK must not be empty; a failed upload can leave a zero-byte asset that downloads
        # happily and installs nothing.
        foreach ($a in $r.assets) {
            if ($a.size -lt 1024) { Bad "$($r.tag_name)/$($a.name) is only $($a.size) bytes"; $problem = $true }
        }
    }

    # The tag each release points at must exist, or the release is orphaned.
    foreach ($r in $rels) {
        try {
            $null = Api "/git/ref/tags/$($r.tag_name)"
            Ok "refs/tags/$($r.tag_name) exists"
        } catch {
            Bad "refs/tags/$($r.tag_name) is missing - the release is orphaned"; $problem = $true
        }
    }

    $latest = Api "/releases/latest"
    if ($latest.tag_name -eq $want) {
        Ok "/releases/latest -> $($latest.tag_name)  (matches VERSION.properties)"
    } else {
        Bad "/releases/latest -> $($latest.tag_name) but VERSION.properties says $want"
        Info "latest resolves by publication time, not version. Fix with:"
        Info "  PATCH /releases/$($latest.id)  {""make_latest"": ""false""}"
        Info "  PATCH /releases/<the $want release id>  {""make_latest"": ""true""}"
        $problem = $true
    }

    # Every version that was published should be listed in VERSIONS.md, so the two cannot drift.
    $versionsDoc = Get-Content (Join-Path $ProjectDir "VERSIONS.md") -Raw
    foreach ($r in $rels) {
        if ($versionsDoc -notmatch [regex]::Escape($r.tag_name)) {
            Warn "$($r.tag_name) exists but VERSIONS.md does not mention it"
        }
    }

    Write-Host ""
    if ($problem) { Bad "problems found - see above"; exit 1 }
    Ok "all checks passed"
    return
}

# --------------------------------------------------------------------------- replace an asset

if ($ReplaceAsset) {
    if (-not $OnRelease) { Bad "-ReplaceAsset needs -OnRelease <tag>"; exit 1 }
    Step "Replacing $ReplaceAsset on $OnRelease"
    Warn "this DELETES the uploaded asset and uploads the local copy"
    Warn "GitHub cannot overwrite an asset; there is no other way to do this"

    $rel = Api "/releases/tags/$OnRelease"
    $old = $rel.assets | Where-Object { $_.name -eq $ReplaceAsset }
    $local = Join-Path $ApkDir $ReplaceAsset
    if (-not (Test-Path $local)) { Bad "no local file at $local"; exit 1 }

    if ($old) {
        Info "deleting the existing asset (id $($old.id), $([math]::Round($old.size/1KB,1)) KB, $($old.download_count) downloads)"
        Api "/releases/assets/$($old.id)" -Method Delete | Out-Null
    } else {
        Info "no existing asset by that name; uploading fresh"
    }
    $url = "https://uploads.github.com/repos/$Repo/releases/$($rel.id)/assets?name=$ReplaceAsset"
    $up = Invoke-RestMethod -Uri $url -Method Post -Headers $Headers -InFile $local `
          -ContentType "application/vnd.android.package-archive" -TimeoutSec 1800
    Ok "uploaded $([math]::Round($up.size/1KB,1)) KB"
    Info "the download URL is unchanged: it is keyed by the release and the asset name"
    return
}

# --------------------------------------------------------------------------- create

if ($Create) {
    $v = Get-Version
    $name = $v["versionName"]
    $tag = "v$name"
    Step "Publishing $tag (versionCode $($v['versionCode']))"

    # **Refuse rather than rename.** If this version is already published, the correct action is
    # either to bump the version or to replace an asset - never to move the existing release.
    $existing = $null
    try { $existing = Api "/releases/tags/$tag" } catch { $existing = $null }
    if ($existing) {
        Bad "$tag already has a release (id $($existing.id), published $($existing.published_at))"
        Info "not touching it. A release is a published artifact; renaming or deleting one breaks"
        Info "links that were already handed out and cannot be undone."
        Info ""
        Info "to publish a change, bump the version first:"
        Info "  powershell -File app/build.ps1 -Bump"
        Info "to refresh a file inside it:"
        Info "  ./release.ps1 -ReplaceAsset bot-panel.apk -OnRelease $tag"
        exit 1
    }

    # The tag has to exist before the release, because releasing with a tag_name that is already
    # taken by a ref and a target_commitish returns 422 - the docs call target_commitish "ignored"
    # in that case; it is not.
    $head = (git -C $ProjectDir rev-parse HEAD).Trim()
    $dirty = git -C $ProjectDir status --porcelain
    if ($dirty) { Warn "the working tree has uncommitted changes; the tag will point at $($head.Substring(0,8)) anyway" }

    $tagExists = $false
    try { $null = Api "/git/ref/tags/$tag"; $tagExists = $true } catch { $tagExists = $false }

    if (-not $tagExists) {
        Info "creating tag $tag at $($head.Substring(0,8))"
        & git -C $ProjectDir tag -a $tag -m "Release $tag" 2>&1 | Out-Null
        & git -C $ProjectDir push origin $tag 2>&1 | Select-Object -Last 1 | ForEach-Object { Info $_ }
    } else {
        Info "tag $tag already exists; reusing it"
    }

    $body = if ($Notes -and (Test-Path $Notes)) {
        Get-Content $Notes -Raw
    } else {
        "See [VERSIONS.md](https://github.com/$Repo/blob/main/VERSIONS.md) for what changed in this version."
    }

    # No target_commitish once the tag exists - see above.
    $release = Api "/releases" -Method Post -Body @{
        tag_name   = $tag
        name       = "$tag — Android 安裝套件"
        body       = $body
        draft      = [bool]$Draft
        prerelease = $false
    }
    Ok "created $(if ($Draft) { 'draft ' })$($release.html_url)"

    Step "Uploading assets from $ApkDir"
    $files = @(
        @{ path = (Join-Path $ApkDir "bot-panel.apk");   name = "bot-panel.apk" },
        @{ path = (Join-Path $ApkDir "termux-api.apk");  name = "termux-api.apk" },
        @{ path = (Join-Path $ApkDir "termux-boot.apk"); name = "termux-boot.apk" }
    )
    foreach ($f in $files) {
        if (-not (Test-Path $f.path)) { Warn "skipping $($f.name): not in $ApkDir"; continue }
        $url = "https://uploads.github.com/repos/$Repo/releases/$($release.id)/assets?name=$($f.name)"
        $up = Invoke-RestMethod -Uri $url -Method Post -Headers $Headers -InFile $f.path `
              -ContentType "application/vnd.android.package-archive" -TimeoutSec 1800
        Ok "$($f.name)  $([math]::Round($up.size/1KB,1)) KB"
    }
    Info "termux.apk (108.6 MB) is not in the repository - upload it by hand, or leave it and"
    Info "point at an older release, since the Termux build has not changed."

    # **Say which release is newest.** GitHub resolves /releases/latest by publication time, so a
    # rebuilt older release silently becomes "latest" and the README's link starts serving it.
    if (-not $Draft) {
        $patch = $release
        $patch.make_latest = "true"
        $null = Api "/releases/$($release.id)" -Method Patch -Body @{ make_latest = "true" }
        Ok "marked as the latest release"
    }

    Write-Host ""
    Info "verify with:  ./release.ps1 -Verify"
    return
}
