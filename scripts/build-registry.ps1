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
    $tier = if ($meta.tier) { $meta.tier } else { "free" }

    if ($tier -eq "premium") {
        # 付费技能：dist 只放 AES 加密包（license-tool pack 预先产出到技能目录 pkg/ 下），
        # 明文源码绝不打包进公开 dist；无加密包则跳过（等运营补包）
        $encSrc = Get-ChildItem -Path (Join-Path $skillDir "pkg") -Filter *.enc -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $encSrc) {
            Write-Warning "skip $($meta.name)@$($meta.version): premium skill missing pkg/*.enc (run license-tool pack first)"
            continue
        }
        $zipName = "$($meta.name)-$($meta.version).zip.enc"
        $zipPath = Join-Path $OutDir "dist/$zipName"
        Copy-Item $encSrc.FullName $zipPath -Force
    } else {
        # 免费技能：打包技能目录内容（排除 pkg/ 加密包存放目录）
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        $items = Get-ChildItem -Path $skillDir | Where-Object { $_.Name -ne "pkg" }
        Compress-Archive -Path $items.FullName -DestinationPath $zipPath
    }
    $sha = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = (Get-Item $zipPath).Length
    $encNote = if ($tier -eq "premium") { " [premium, encrypted]" } else { "" }

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
    Write-Host "  packaged $($meta.name)@$($meta.version)$encNote -> $zipName (sha256 $($sha.Substring(0,12))...)"
}

$registry = [ordered]@{
    version            = "0.2.0"
    min_client_version = "0.1.0"
    updated_at         = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    skills             = ($entries | Sort-Object name)
}
$registry | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutDir "registry.json") -Encoding utf8
Write-Host "registry: $($entries.Count) skills -> $OutDir/registry.json"
