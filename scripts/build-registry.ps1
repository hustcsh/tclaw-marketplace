# build-registry.ps1 —— Windows 本地验证版（与 build-registry.sh 产物一致）
# 用法: pwsh ./scripts/build-registry.ps1 -SkillsDir <tclaw-skills-dir> [-OutDir public]
param(
    [Parameter(Mandatory = $true)][string]$SkillsDir,
    [string]$OutDir = "public"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $SkillsDir)) { throw "skills dir not found: $SkillsDir" }
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "dist") | Out-Null

$entries = @()
$manifests = Get-ChildItem -Path $SkillsDir -Filter manifest.json -Recurse -Depth 1
foreach ($manifest in $manifests) {
    $skillDir = $manifest.Directory
    $meta = Get-Content $manifest.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $meta.name -or -not $meta.version) {
        Write-Warning "skip $($manifest.FullName): missing name/version"
        continue
    }
    $zipName = "$($meta.name)-$($meta.version).zip"
    $zipPath = Join-Path $OutDir "dist/$zipName"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $skillDir "*") -DestinationPath $zipPath
    $sha = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = (Get-Item $zipPath).Length

    $entries += [ordered]@{
        name          = $meta.name
        display_name  = $meta.display_name
        description   = $meta.description
        version       = $meta.version
        type          = $meta.type
        tier          = $meta.tier
        agent_compat  = $meta.agent_compat
        categories    = $meta.categories
        permissions   = $meta.permissions
        compat        = $meta.compat
        apis          = $meta.apis
        channel       = $meta.channel
        downloads     = @(
            [ordered]@{ platform = "any"; url = "dist/$zipName"; sha256 = $sha; size = $size }
        )
    }
    Write-Host "  packaged $($meta.name)@$($meta.version) -> $zipName (sha256 $($sha.Substring(0,12))...)"
}

$registry = [ordered]@{
    version            = "0.2.0"
    min_client_version = "0.1.0"
    updated_at         = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    skills             = ($entries | Sort-Object name)
}
$registry | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutDir "registry.json") -Encoding utf8
Write-Host "registry: $($entries.Count) skills -> $OutDir/registry.json"
