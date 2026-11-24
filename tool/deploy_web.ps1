<#
.SYNOPSIS
  Builds the Flutter web app and publishes it to the GitHub Pages branch.

.DESCRIPTION
  1. Makes sure you are on the source branch (switches automatically when run
     from the deploy branch) and that the working tree is clean.
  2. Runs `flutter pub get`, `flutter analyze` and `flutter test`.
  3. Builds with `--base-href /piano_roll/` into build/pages.
  4. Replaces the contents of the deploy branch (default: web_deploy) with the
     build output in a temporary git worktree, so your working tree and
     checked-out branch are never disturbed, and commits it.
  5. Tags the source commit `v<version>` and the deploy commit
     `deploy-<version>-<UTC timestamp>` (version = pubspec.yaml `version:`).
  6. With -Push, pushes the deploy branch and the new tags.

  Nothing is pushed unless -Push is given.

.PARAMETER Push
  Push the deploy branch and the new tags to the remote.
.PARAMETER SkipChecks
  Skip `flutter analyze` and `flutter test`.
.PARAMETER AllowDirty
  Build even with uncommitted changes. The source tag is then NOT created
  because the build would not correspond to a commit.
.PARAMETER SourceBranch
  Branch the app is built from. Default: the current branch, or `main` when
  run from the deploy branch.
.PARAMETER DeployBranch
  Branch served by GitHub Pages. Default: web_deploy.
.PARAMETER BaseHref
  URL path the site is served from. Must start and end with '/'.
.PARAMETER Remote
  Git remote name. Default: origin.
.PARAMETER OutputDir
  Folder (relative to the repo root) that receives the build. Default: build/pages.

.EXAMPLE
  .\tool\deploy_web.ps1            # build, commit and tag locally
  .\tool\deploy_web.ps1 -Push      # ...and publish
#>
[CmdletBinding()]
param(
  [string]$SourceBranch = '',
  [string]$DeployBranch = 'web_deploy',
  [string]$Remote = 'origin',
  [string]$BaseHref = '/piano_roll/',
  [string]$OutputDir = 'build/pages',
  [switch]$Push,
  [switch]$SkipChecks,
  [switch]$AllowDirty
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Warn([string]$Message) { Write-Host "WARNING: $Message" -ForegroundColor Yellow }

# All helpers take the argument list as ONE array so that dashed arguments
# such as `-C` are never interpreted as PowerShell parameters.

# Runs git; throws on a non-zero exit code.
function Invoke-Git([string[]]$GitArgs) {
  & git @GitArgs
  if ($LASTEXITCODE -ne 0) { throw "'git $($GitArgs -join ' ')' failed with exit code $LASTEXITCODE." }
}

# Runs git and returns its trimmed stdout; throws on failure.
function Get-Git([string[]]$GitArgs) {
  $out = & git @GitArgs
  if ($LASTEXITCODE -ne 0) { throw "'git $($GitArgs -join ' ')' failed with exit code $LASTEXITCODE." }
  if ($null -eq $out) { return '' }
  return (($out | Out-String).Trim())
}

# Runs git and returns $true when it succeeds (all output discarded).
function Test-Git([string[]]$GitArgs) {
  & git @GitArgs *> $null
  return ($LASTEXITCODE -eq 0)
}

# Runs any other native command (flutter); throws on a non-zero exit code.
function Invoke-Native([string]$Command, [string[]]$CommandArgs) {
  & $Command @CommandArgs
  if ($LASTEXITCODE -ne 0) { throw "'$Command $($CommandArgs -join ' ')' failed with exit code $LASTEXITCODE." }
}

if ($BaseHref -notmatch '^/.*/$') {
  throw "BaseHref must start and end with '/', e.g. '/piano_roll/'. Got '$BaseHref'."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot

foreach ($tool in 'git', 'flutter') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "'$tool' was not found on PATH." }
}
if (-not (Test-Git 'rev-parse', '--is-inside-work-tree')) { throw "$repoRoot is not a git repository." }

# --- Source branch -----------------------------------------------------------
$current = ''
$symbolic = & git symbolic-ref --short -q HEAD 2>$null
if ($LASTEXITCODE -eq 0 -and $symbolic) { $current = ($symbolic | Out-String).Trim() }

if (-not $SourceBranch) {
  if ($current -and $current -ne $DeployBranch) { $SourceBranch = $current } else { $SourceBranch = 'main' }
}
if ($SourceBranch -eq $DeployBranch) {
  throw "The source branch and the deploy branch are both '$DeployBranch'."
}
if (-not (Test-Git 'show-ref', '--verify', '--quiet', "refs/heads/$SourceBranch")) {
  throw "Source branch '$SourceBranch' does not exist."
}

$dirty = Get-Git 'status', '--porcelain'
if ($current -ne $SourceBranch) {
  if ($dirty) {
    throw "Uncommitted changes on '$current'. Commit or stash them before the script switches to '$SourceBranch'."
  }
  Write-Step "Switching from '$current' to '$SourceBranch'"
  Invoke-Git 'switch', $SourceBranch
  $dirty = Get-Git 'status', '--porcelain'
}

$tagSource = $true
if ($dirty) {
  if (-not $AllowDirty) {
    throw "The working tree has uncommitted changes:`n$dirty`nCommit them (so the release tag matches the build) or pass -AllowDirty."
  }
  Write-Warn 'Building with uncommitted changes; the source tag will not be created.'
  $tagSource = $false
}

$srcSha = Get-Git 'rev-parse', 'HEAD'
$srcShort = Get-Git 'rev-parse', '--short', 'HEAD'

# --- Version and tags --------------------------------------------------------
$versionMatch = Select-String -Path (Join-Path $repoRoot 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $versionMatch) { throw 'Could not find a "version:" line in pubspec.yaml.' }
$version = $versionMatch.Matches[0].Groups[1].Value
$sourceTag = "v$version"
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$deployTag = "deploy-$version-$stamp"

$sourceTagExists = $false
if ($tagSource) {
  $existing = & git rev-parse -q --verify "refs/tags/$sourceTag^{commit}" 2>$null
  if ($LASTEXITCODE -eq 0 -and $existing) {
    $existing = ($existing | Out-String).Trim()
    if ($existing -ne $srcSha) {
      throw "Tag $sourceTag already exists on a different commit ($($existing.Substring(0, 7))). Bump 'version:' in pubspec.yaml."
    }
    $sourceTagExists = $true
  }
}

$haveRemote = ((& git remote) -contains $Remote)
if ($haveRemote -and (Test-Git 'show-ref', '--verify', '--quiet', "refs/remotes/$Remote/$SourceBranch")) {
  $behind = [int](Get-Git 'rev-list', '--count', "HEAD..$Remote/$SourceBranch")
  if ($behind -gt 0) { Write-Warn "'$SourceBranch' is $behind commit(s) behind $Remote/$SourceBranch." }
}

Write-Host "Source:  $SourceBranch @ $srcShort"
Write-Host "Version: $version"
Write-Host "Deploy:  $DeployBranch  (base href $BaseHref)"

# --- Checks and build --------------------------------------------------------
Write-Step 'flutter pub get'
Invoke-Native 'flutter' 'pub', 'get'
if (-not $SkipChecks) {
  Write-Step 'flutter analyze'
  Invoke-Native 'flutter' 'analyze'
  Write-Step 'flutter test'
  Invoke-Native 'flutter' 'test'
}

$outPath = Join-Path $repoRoot $OutputDir
if (Test-Path $outPath) { Remove-Item -Recurse -Force $outPath }
Write-Step "flutter build web --release --base-href $BaseHref --output $OutputDir"
Invoke-Native 'flutter' 'build', 'web', '--release', '--base-href', $BaseHref, '--output', $OutputDir

$indexPath = Join-Path $outPath 'index.html'
if (-not (Test-Path $indexPath)) { throw "Build output is missing $indexPath." }
if (-not (Select-String -Path $indexPath -SimpleMatch -Pattern "<base href=`"$BaseHref`">" -Quiet)) {
  throw "index.html does not contain <base href=`"$BaseHref`">; the build base href is wrong."
}

# --- Deploy branch via a temporary worktree ----------------------------------
$worktree = Join-Path $repoRoot 'build/.deploy_worktree'
function Remove-DeployWorktree {
  if (Test-Path $worktree) {
    & git worktree remove --force $worktree *> $null
    if (Test-Path $worktree) { Remove-Item -Recurse -Force $worktree }
  }
  & git worktree prune *> $null
}

$deployed = $false
$deploySha = ''
try {
  Remove-DeployWorktree

  if ($haveRemote) {
    Write-Step "Fetching $Remote/$DeployBranch"
    & git fetch $Remote $DeployBranch *> $null
    if ($LASTEXITCODE -ne 0) { Write-Warn "Could not fetch $Remote/$DeployBranch (first publish, or offline?)." }
  }
  $localExists = Test-Git 'show-ref', '--verify', '--quiet', "refs/heads/$DeployBranch"
  $remoteExists = Test-Git 'show-ref', '--verify', '--quiet', "refs/remotes/$Remote/$DeployBranch"

  Write-Step "Preparing worktree for '$DeployBranch'"
  if ($localExists) {
    Invoke-Git 'worktree', 'add', $worktree, $DeployBranch
    if ($remoteExists) {
      $behind = [int](Get-Git 'rev-list', '--count', "$DeployBranch..$Remote/$DeployBranch")
      $ahead = [int](Get-Git 'rev-list', '--count', "$Remote/$DeployBranch..$DeployBranch")
      if ($behind -gt 0 -and $ahead -gt 0) {
        throw "Local $DeployBranch and $Remote/$DeployBranch have diverged. Reconcile them manually."
      }
      if ($behind -gt 0) { Invoke-Git '-C', $worktree, 'merge', '--ff-only', "$Remote/$DeployBranch" }
    }
  } elseif ($remoteExists) {
    Invoke-Git 'worktree', 'add', '-b', $DeployBranch, $worktree, "$Remote/$DeployBranch"
  } else {
    Write-Warn "Branch '$DeployBranch' does not exist yet; creating it as an orphan branch."
    Invoke-Git 'worktree', 'add', '--detach', $worktree
    Invoke-Git '-C', $worktree, 'checkout', '--orphan', $DeployBranch
    & git -C $worktree rm -rf --quiet . *> $null
  }

  Write-Step 'Replacing branch contents with the build output'
  Get-ChildItem -LiteralPath $worktree -Force |
    Where-Object { $_.Name -ne '.git' } |
    Remove-Item -Recurse -Force
  Get-ChildItem -LiteralPath $outPath -Force |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $worktree -Recurse -Force }
  # Serve files as-is: GitHub Pages must not run Jekyll over Flutter's assets,
  # and git must not normalise line endings (Windows autocrlf would alter
  # files whose bytes contain CRLF, breaking the service worker's file hashes).
  New-Item -ItemType File -Path (Join-Path $worktree '.nojekyll') -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $worktree '.gitattributes') -Value '* -text' -Encoding ascii

  Invoke-Git '-c', 'core.autocrlf=false', '-c', 'core.safecrlf=false', '-C', $worktree, 'add', '-A'
  $staged = Get-Git '-C', $worktree, 'status', '--porcelain'
  if (-not $staged) {
    Write-Step "No changes compared with '$DeployBranch'; nothing to commit."
  } else {
    $subject = "Deploy $version ($srcShort)"
    $body = "Source: $SourceBranch @ $srcSha`nBase href: $BaseHref`nBuilt: $stamp UTC by tool/deploy_web.ps1"
    Write-Step "Committing: $subject"
    Invoke-Git '-C', $worktree, 'commit', '--quiet', '-m', $subject, '-m', $body
    $deployed = $true
    $deploySha = Get-Git '-C', $worktree, 'rev-parse', 'HEAD'
  }
} finally {
  Remove-DeployWorktree
}

# --- Tags --------------------------------------------------------------------
$createdTags = @()
if ($tagSource -and -not $sourceTagExists) {
  Invoke-Git 'tag', '-a', $sourceTag, '-m', "Release $version", $srcSha
  $createdTags += $sourceTag
}
if ($deployed) {
  Invoke-Git 'tag', '-a', $deployTag, '-m', "Deploy $version from $srcShort", $deploySha
  $createdTags += $deployTag
}
if ($createdTags.Count -gt 0) { Write-Step "Created tag(s): $($createdTags -join ', ')" }

# --- Push --------------------------------------------------------------------
if ($Push) {
  if (-not $haveRemote) { throw "Remote '$Remote' does not exist." }
  # Push every release/deploy tag, not just this run's, so tags created by
  # earlier runs without -Push are published too (already-pushed ones are no-ops).
  $tagRefs = @()
  foreach ($pattern in 'v*', 'deploy-*') {
    $names = Get-Git 'tag', '--list', $pattern
    if ($names) {
      $tagRefs += @($names -split "\r?\n" | Where-Object { $_ } | ForEach-Object { "refs/tags/$_" })
    }
  }
  Write-Step "Pushing $DeployBranch and $($tagRefs.Count) tag(s) to $Remote"
  Invoke-Git (@('push', $Remote, "refs/heads/${DeployBranch}:refs/heads/$DeployBranch") + $tagRefs)
  if (Test-Git 'show-ref', '--verify', '--quiet', "refs/remotes/$Remote/$SourceBranch") {
    $unpushed = [int](Get-Git 'rev-list', '--count', "$Remote/${SourceBranch}..$SourceBranch")
    if ($unpushed -gt 0 -and $tagSource) {
      Write-Warn "'$SourceBranch' has $unpushed unpushed commit(s); push it too: git push $Remote $SourceBranch"
    }
  }
}

# --- Summary -----------------------------------------------------------------
Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
if ($deployed) { Write-Host "  $DeployBranch -> $($deploySha.Substring(0, 7))  (tag $deployTag)" }
$remoteUrl = ''
if ($haveRemote) { $remoteUrl = Get-Git 'remote', 'get-url', $Remote }
if ($remoteUrl -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(\.git)?$') {
  $repoName = $Matches['repo']
  Write-Host "  Site: https://$($Matches['owner']).github.io/$repoName/"
  if ($BaseHref -ne "/$repoName/") {
    Write-Warn "BaseHref '$BaseHref' does not match the repository name '/$repoName/'; a project Pages site will not load its assets."
  }
}
if (-not $Push) {
  Write-Host "  Not pushed. Publish with:  .\tool\deploy_web.ps1 -Push"
}
Write-Host "  GitHub: Settings > Pages > Source = 'Deploy from a branch', branch $DeployBranch, folder / (root)."
