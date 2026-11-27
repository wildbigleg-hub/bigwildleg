<#
.SYNOPSIS
    bigwildleg 原型发布工具

.DESCRIPTION
    把一个原型目录（Axure 9 导出的 HTML 或 Agent 生成的 HTML）发布到
    <公司>/<项目>/ 下，自动更新首页入口，然后提交并推送到 GitHub。

.EXAMPLE
    .\publish.ps1 -Company MTH -Project aixiangxinsheng -Source "D:\导出\艾享新生" -ProjectName "艾享新生"

.EXAMPLE
    .\publish.ps1 -Company MTH -Project zaokouwuyou -Source "C:\临时\zaokouwuyou.html" -ProjectName "早口无忧"

.EXAMPLE
    .\publish.ps1 -Rebuild
    只重建首页（手动加过目录时用），不发布新原型。
#>
[CmdletBinding()]
param(
    [string]$Company,
    [string]$Project,
    [string]$Source,
    [string]$ProjectName,
    [string]$CompanyName,
    [switch]$Rebuild,
    [switch]$NoPush
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$MetaPath = Join-Path $RepoRoot 'projects.json'
$PortalPath = Join-Path $RepoRoot 'index.html'
$IgnoreDirs = @('.git', '.github', '.vscode')

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Read-Meta {
    $meta = @{
        Companies = @{}
        Projects  = @()
    }
    if (Test-Path $MetaPath) {
        try {
            $json = Get-Content $MetaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            throw "projects.json 格式有问题，请检查：$($_.Exception.Message)"
        }
        if ($json.companies) {
            foreach ($p in $json.companies.PSObject.Properties) {
                $display = [string]$p.Value.displayName
                if ([string]::IsNullOrWhiteSpace($display)) { $display = $p.Name }
                $meta.Companies[$p.Name] = $display
            }
        }
        if ($json.projects) {
            foreach ($p in $json.projects) {
                $meta.Projects += [pscustomobject]@{
                    Company = [string]$p.company
                    Project = [string]$p.project
                    Title   = [string]$p.title
                    Updated = [string]$p.updated
                }
            }
        }
    }
    return $meta
}

function Get-DiskProjects {
    $result = @()
    Get-ChildItem $RepoRoot -Directory -Force |
        Where-Object {
            $_.Name -notin $IgnoreDirs -and
            -not $_.Name.StartsWith('.') -and
            -not $_.Name.StartsWith('_')
        } |
        ForEach-Object {
            $companyDir = $_
            Get-ChildItem $companyDir.FullName -Directory |
                ForEach-Object {
                    if (Test-Path (Join-Path $_.FullName 'index.html')) {
                        $script:diskProjects += [pscustomobject]@{
                            Company = $companyDir.Name
                            Project = $_.Name
                        }
                    }
                }
        }
    return $script:diskProjects
}

function Sync-Meta {
    param($Meta)
    $script:diskProjects = @()
    $disk = @(Get-DiskProjects)
    $existing = @{}
    foreach ($p in $Meta.Projects) {
        $existing["$($p.Company)/$($p.Project)"] = $p
    }
    $merged = @()
    foreach ($d in $disk) {
        $key = "$($d.Company)/$($d.Project)"
        if ($existing.ContainsKey($key)) {
            $m = $existing[$key]
            $merged += [pscustomobject]@{
                Company = $m.Company
                Project = $m.Project
                Title   = $m.Title
                Updated = $m.Updated
            }
        }
        else {
            $merged += [pscustomobject]@{
                Company = $d.Company
                Project = $d.Project
                Title   = $d.Project
                Updated = ''
            }
        }
    }
    $Meta.Projects = $merged
    return $Meta
}

function Save-Meta {
    param($Meta)
    $companiesObj = [ordered]@{}
    foreach ($k in ($Meta.Companies.Keys | Sort-Object)) {
        $companiesObj[$k] = [ordered]@{ displayName = $Meta.Companies[$k] }
    }
    $projectsArr = @()
    foreach ($p in ($Meta.Projects | Sort-Object Company, Project)) {
        $projectsArr += [ordered]@{
            company = $p.Company
            project = $p.Project
            title   = $p.Title
            updated = $p.Updated
        }
    }
    $obj = [ordered]@{
        companies = $companiesObj
        projects  = $projectsArr
    }
    Write-Utf8NoBom -Path $MetaPath -Content ($obj | ConvertTo-Json -Depth 5)
}

function Write-Portal {
    param($Meta)

    $enc = [System.Net.WebUtility]
    $projects = @($Meta.Projects)
    $total = $projects.Count
    $today = Get-Date -Format 'yyyy-MM-dd'

    $groups = @($projects | Group-Object Company | Sort-Object Name)

    $body = New-Object System.Text.StringBuilder
    foreach ($g in $groups) {
        $display = $Meta.Companies[$g.Name]
        if ([string]::IsNullOrWhiteSpace($display)) { $display = $g.Name }

        [void]$body.Append('<section class="company">')
        [void]$body.Append('<div class="company-head"><h2>' + $enc::HtmlEncode($display) + '</h2>')
        if ($display -ne $g.Name) {
            [void]$body.Append('<span class="code">' + $enc::HtmlEncode($g.Name) + '</span>')
        }
        [void]$body.Append('<span class="count">' + $g.Count + ' 个原型</span></div>')
        [void]$body.Append('<div class="grid">')

        foreach ($p in ($g.Group | Sort-Object Project)) {
            $title = $p.Title
            if ([string]::IsNullOrWhiteSpace($title)) { $title = $p.Project }
            $href = "$($p.Company)/$($p.Project)/"
            $date = $p.Updated
            if ([string]::IsNullOrWhiteSpace($date)) { $date = '—' }
            $key = (($title + ' ' + $p.Project + ' ' + $display + ' ' + $g.Name).ToLower())

            [void]$body.Append('<a class="card" href="' + $enc::HtmlEncode($href) + '" data-key="' + $enc::HtmlEncode($key) + '">')
            [void]$body.Append('<div class="card-title">' + $enc::HtmlEncode($title) + '</div>')
            [void]$body.Append('<div class="card-path">' + $enc::HtmlEncode($href) + '</div>')
            [void]$body.Append('<div class="card-foot"><span class="date">' + $enc::HtmlEncode($date) + '</span><span class="go">打开 →</span></div>')
            [void]$body.Append('</a>')
        }

        [void]$body.Append('</div></section>')
    }

    $head = @'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>原型预览 · bigwildleg</title>
<style>
  :root { --ink:#1b2431; --muted:#6b7684; --line:#e6e9ef; --accent:#1d4ed8; --bg:#f5f7fa; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--ink);
         font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
         -webkit-font-smoothing: antialiased; }
  .wrap { max-width: 1080px; margin: 0 auto; padding: 0 24px; }
  header { background:#fff; border-bottom:1px solid var(--line); padding:44px 0 30px; }
  .brand { display:flex; align-items:center; gap:10px; font-size:22px; font-weight:700; letter-spacing:.5px; }
  .dot { width:10px; height:10px; border-radius:50%; background:var(--accent); box-shadow:0 0 0 4px rgba(29,78,216,.12); }
  .sub { margin-top:10px; color:var(--muted); font-size:14px; }
  .search { margin-top:22px; width:100%; max-width:420px; padding:11px 14px; font-size:14px;
            border:1px solid var(--line); border-radius:10px; background:#fafbfc; color:var(--ink); outline:none; }
  .search:focus { border-color:var(--accent); background:#fff; box-shadow:0 0 0 3px rgba(29,78,216,.1); }
  main { padding: 30px 0 60px; }
  .meta-line { color:var(--muted); font-size:13px; margin-bottom:22px; }
  .company { margin-bottom: 34px; }
  .company-head { display:flex; align-items:baseline; gap:10px; margin-bottom:14px; }
  .company-head h2 { margin:0; font-size:17px; font-weight:650; }
  .code { font-size:12px; color:var(--muted); background:#eef1f5; padding:2px 8px; border-radius:6px; }
  .count { margin-left:auto; font-size:12px; color:var(--muted); }
  .grid { display:grid; grid-template-columns: repeat(auto-fill, minmax(258px, 1fr)); gap:14px; }
  .card { display:block; background:#fff; border:1px solid var(--line); border-radius:14px;
          padding:18px 18px 14px; text-decoration:none; color:inherit;
          transition: transform .15s ease, box-shadow .15s ease, border-color .15s ease; }
  .card:hover { transform: translateY(-2px); border-color:#cfd8e6; box-shadow:0 10px 24px rgba(20,35,60,.08); }
  .card-title { font-size:16px; font-weight:600; margin-bottom:6px; }
  .card-path { font-size:12px; color:var(--muted); word-break:break-all; }
  .card-foot { display:flex; justify-content:space-between; align-items:center;
               margin-top:18px; padding-top:12px; border-top:1px solid var(--line);
               font-size:12px; color:var(--muted); }
  .go { color:var(--accent); font-weight:600; }
  .empty { text-align:center; color:var(--muted); padding:50px 0; font-size:14px; }
  footer { border-top:1px solid var(--line); padding:22px 0 40px; color:var(--muted); font-size:12px; }
</style>
</head>
<body>
<header>
  <div class="wrap">
    <div class="brand"><span class="dot"></span>原型预览</div>
    <div class="sub">各项目原型的最新可交互版本，点击卡片直接在线查看。</div>
    <input id="q" class="search" type="search" placeholder="搜索公司 / 项目名称" autocomplete="off">
  </div>
</header>
<main class="wrap">
'@

    $metaLine = '<div class="meta-line">共 <strong>' + $total + '</strong> 个原型 · 更新于 ' + $today + '</div>'

    $tail = @'
  <div id="empty" class="empty" hidden>没有匹配的原型</div>
</main>
<footer>
  <div class="wrap">仅供内部与客户预览，请勿外传 · GitHub Pages 自动发布</div>
</footer>
<script>
  var q = document.getElementById('q');
  function filter() {
    var v = (q.value || '').trim().toLowerCase();
    var visible = 0;
    document.querySelectorAll('.card').forEach(function (c) {
      var hit = !v || (c.getAttribute('data-key') || '').indexOf(v) > -1;
      c.style.display = hit ? '' : 'none';
      if (hit) visible++;
    });
    document.querySelectorAll('.company').forEach(function (s) {
      var shown = s.querySelectorAll('.card:not([style*="none"])').length;
      s.style.display = shown ? '' : 'none';
    });
    document.getElementById('empty').hidden = visible > 0;
  }
  q.addEventListener('input', filter);
</script>
</body>
</html>
'@

    $html = $head + $metaLine + $body.ToString() + $tail
    Write-Utf8NoBom -Path $PortalPath -Content $html
    Write-Host "首页已更新：index.html（$total 个原型）" -ForegroundColor Green
}

function Invoke-GitPublish {
    param([string]$Message)
    Push-Location $RepoRoot
    try {
        git add -A
        git commit -m $Message | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "没有需要提交的改动。" -ForegroundColor Yellow
            return
        }
        Write-Host "已提交：$Message" -ForegroundColor Green
        $remotes = @(git remote)
        if ($NoPush) {
            Write-Host "已跳过推送（-NoPush）。" -ForegroundColor Yellow
        }
        elseif ($remotes.Count -eq 0) {
            Write-Host "还没配置远程仓库，先执行：git remote add origin git@github.com:wildbigleg-hub/bigwildleg.git" -ForegroundColor Yellow
        }
        else {
            git push
            if ($LASTEXITCODE -eq 0) {
                Write-Host "已推送到 GitHub，约 1 分钟后线上生效。" -ForegroundColor Green
            }
            else {
                throw "推送失败，请检查 SSH 公钥是否已添加到 GitHub。"
            }
        }
    }
    finally {
        Pop-Location
    }
}

# ---------- 主流程 ----------

$meta = Read-Meta

if ($Rebuild) {
    $meta = Sync-Meta -Meta $meta
    Save-Meta -Meta $meta
    Write-Portal -Meta $meta
    if (-not $NoPush) {
        Invoke-GitPublish -Message "chore: 重建原型首页"
    }
    return
}

if (-not $Company -and -not $Project -and -not $Source) {
    Write-Host "用法：" -ForegroundColor Yellow
    Write-Host "  .\publish.ps1 -Company MTH -Project aixiangxinsheng -Source <原型目录或html文件> [-ProjectName 显示名]"
    Write-Host "  .\publish.ps1 -Rebuild    # 只重建首页"
    return
}

if (-not $Company -or -not $Project -or -not $Source) {
    Write-Host "用法：.\publish.ps1 -Company MTH -Project aixiangxinsheng -Source <原型目录或html文件> [-ProjectName 显示名]" -ForegroundColor Yellow
    throw "缺少参数：Company / Project / Source 三个都要给。"
}

if ($Company -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
    throw "公司文件夹名只能包含字母、数字、- 和 _（建议用缩写，例如 MTH）。"
}
if ($Project -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
    throw "项目文件夹名只能包含字母、数字、- 和 _（建议用拼音，例如 aixiangxinsheng）。中文名请放到 -ProjectName 参数里。"
}
if (-not (Test-Path $Source)) {
    throw "找不到源文件或目录：$Source"
}

$src = (Resolve-Path $Source).Path
$isSingleFile = Test-Path $src -PathType Leaf

# 源是单个 html 文件
if ($isSingleFile) {
    if ([IO.Path]::GetExtension($src).ToLower() -notin @('.html', '.htm')) {
        throw "源文件必须是 .html / .htm，或者传一个目录。"
    }
}
else {
    if (-not (Test-Path (Join-Path $src 'index.html'))) {
        # 兼容把导出文件夹整个拖进来的情况：自动往下找一层
        $subs = @(Get-ChildItem $src -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'index.html') })
        if ($subs.Count -eq 1) {
            $src = $subs[0].FullName
            Write-Host "自动定位到子目录：$src" -ForegroundColor DarkGray
        }
        else {
            throw "源目录里没找到 index.html。Axure 导出时请把整个导出文件夹（含 index.html、resources、data 等）一起传入。"
        }
    }
}

$staging = Join-Path $env:TEMP "bigwildleg-stage-$Company-$Project"
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null

if ($isSingleFile) {
    Copy-Item $src (Join-Path $staging 'index.html') -Force
}
else {
    $null = robocopy $src $staging /E /NFL /NDL /NJH /NJS /XD ".git" "node_modules" ".vscode" /XF "Thumbs.db" "desktop.ini" "*.rp"
    if ($LASTEXITCODE -ge 8) {
        throw "复制文件失败（robocopy 退出码 $LASTEXITCODE）。"
    }
}

if (-not (Test-Path (Join-Path $staging 'index.html'))) {
    throw "复制后没有 index.html，请确认导出是否完整。"
}

$target = Join-Path (Join-Path $RepoRoot $Company) $Project
if (Test-Path $target) {
    $backup = Join-Path $env:TEMP ("bigwildleg-backup\" + $Company + "-" + $Project + "-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    Copy-Item (Join-Path $target '*') $backup -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $target -Recurse -Force
    Write-Host "旧版本已备份到：$backup" -ForegroundColor DarkGray
}

New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
Move-Item $staging $target
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }

# 更新元数据
$match = $meta.Projects | Where-Object { $_.Company -eq $Company -and $_.Project -eq $Project }
if ($match) {
    if (-not [string]::IsNullOrWhiteSpace($ProjectName)) { $match.Title = $ProjectName }
    $match.Updated = (Get-Date -Format 'yyyy-MM-dd')
}
else {
    $title = $ProjectName
    if ([string]::IsNullOrWhiteSpace($title)) { $title = $Project }
    $meta.Projects += [pscustomobject]@{
        Company = $Company
        Project = $Project
        Title   = $title
        Updated = (Get-Date -Format 'yyyy-MM-dd')
    }
}

if (-not [string]::IsNullOrWhiteSpace($CompanyName)) {
    $meta.Companies[$Company] = $CompanyName
}
elseif (-not $meta.Companies.ContainsKey($Company)) {
    $meta.Companies[$Company] = $Company
}

$meta = Sync-Meta -Meta $meta
Save-Meta -Meta $meta
Write-Portal -Meta $meta

Write-Host "已发布：$Company/$Project → $target" -ForegroundColor Green
Invoke-GitPublish -Message "publish: $Company/$Project"
