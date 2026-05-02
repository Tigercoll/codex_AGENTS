param(
    [string]$RepoUrl = "https://github.com/msitarzewski/agency-agents.git",
    [string]$Branch = "main",
    [string]$SourceMirrorPath = "$env:USERPROFILE\.codex\vendor_imports\agency-agents-source",
    [string]$InstallRoot = "$env:USERPROFILE\.codex\agents\agency-agents",
    [string]$MapJsonPath = "$env:USERPROFILE\.codex\agents\agency-agent-map.json",
    [string]$MapMdPath = "$env:USERPROFILE\.codex\agents\agency-agent-map.md",
    [string]$ProfilesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ProfilesPath) {
    $ProfilesPath = Join-Path $ScriptDir "agency-agent-profiles.json"
}

function Format-ExternalCommandForMessage {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    $parts = @($Command)
    foreach ($argument in $Arguments) {
        if ($argument -match '\s') {
            $parts += '"' + ($argument -replace '"', '\"') + '"'
        }
        else {
            $parts += $argument
        }
    }
    return $parts -join ' '
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$CaptureOutput
    )

    if ($CaptureOutput) {
        $output = & $Command @Arguments
    }
    else {
        & $Command @Arguments
        $output = $null
    }

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $commandText = Format-ExternalCommandForMessage -Command $Command -Arguments $Arguments
        throw "External command failed with exit code ${exitCode}: $commandText"
    }

    return $output
}

function ConvertTo-HashtableRecursive {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $hash = [ordered]@{}
        foreach ($prop in $Value.PSObject.Properties) {
            $hash[$prop.Name] = ConvertTo-HashtableRecursive -Value $prop.Value
        }
        return $hash
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,(ConvertTo-HashtableRecursive -Value $item)
        }
        return $items
    }
    return $Value
}

if (-not (Test-Path -LiteralPath $ProfilesPath)) {
    throw "Shared profile definition not found: $ProfilesPath"
}

$SharedConfig = Get-Content -LiteralPath $ProfilesPath -Raw | ConvertFrom-Json
$categoryDirs = @($SharedConfig.category_dirs)
$autoRouteProfiles = ConvertTo-HashtableRecursive -Value $SharedConfig.auto_route_profiles

function Ensure-ParentDirectory {
    param([string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Sync-SourceMirror {
    Ensure-ParentDirectory -Path $SourceMirrorPath
    if (Test-Path -LiteralPath (Join-Path $SourceMirrorPath ".git")) {
        Invoke-ExternalCommand -Command "git" -Arguments @("-C", $SourceMirrorPath, "fetch", "origin", $Branch)
        Invoke-ExternalCommand -Command "git" -Arguments @("-C", $SourceMirrorPath, "checkout", $Branch)
        Invoke-ExternalCommand -Command "git" -Arguments @("-C", $SourceMirrorPath, "reset", "--hard", ("origin/" + $Branch))
    }
    else {
        if (Test-Path -LiteralPath $SourceMirrorPath) {
            Remove-Item -LiteralPath $SourceMirrorPath -Recurse -Force
        }
        Invoke-ExternalCommand -Command "git" -Arguments @("clone", "--depth", "1", "--branch", $Branch, $RepoUrl, $SourceMirrorPath)
    }
}

function Install-AgentTemplates {
    if (Test-Path -LiteralPath $InstallRoot) {
        Remove-Item -LiteralPath $InstallRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    foreach ($dir in $categoryDirs) {
        $sourceDir = Join-Path $SourceMirrorPath $dir
        if (Test-Path -LiteralPath $sourceDir) {
            Copy-Item -LiteralPath $sourceDir -Destination $InstallRoot -Recurse -Force
        }
    }
}

function Get-FrontMatter {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path
    if ($lines.Count -lt 3 -or $lines[0].Trim() -ne "---") {
        return $null
    }
    $result = [ordered]@{}
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line.Trim() -eq "---") {
            return $result
        }
        if ($line -match '^\s*([A-Za-z0-9_-]+)\s*:\s*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()
            $value = $value.Trim('"')
            $result[$key] = $value
        }
    }
    return $null
}

function Convert-ToKey {
    param([string]$Slug)
    return ($Slug -replace '[^A-Za-z0-9_-]', '-') -replace '-', '_'
}

function Get-DefaultMode {
    param([string]$Category, [string]$Slug)
    if ($Category -eq "testing") { return "qa" }
    if ($Slug -like "*reviewer*") { return "reviewer" }
    if ($Slug -like "*orchestrator*") { return "orchestrator" }
    if ($Slug -like "*project-manager*" -or $Slug -like "*planner*") { return "planner" }
    if ($Category -eq "design") { return "design" }
    if ($Category -eq "product") { return "product" }
    if ($Category -eq "project-management") { return "coordinator" }
    return "executor"
}

function Get-DefaultAliases {
    param([string]$Slug, [string]$Label)
    $aliases = New-Object System.Collections.Generic.List[string]
    $aliases.Add($Slug)
    $aliases.Add(($Slug -replace '-', '_'))
    $aliases.Add(($Label.ToLowerInvariant() -replace '[^a-z0-9]+', '-'))
    return $aliases | Select-Object -Unique
}

function Normalize-RelativePath {
    param([string]$Path)
    return $Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar).Replace('\', [System.IO.Path]::DirectorySeparatorChar)
}

function Get-RelativePathCompat {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )
    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFull += [System.IO.Path]::DirectorySeparatorChar
    }
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    $relative = $baseUri.MakeRelativeUri($targetUri).ToString()
    return [System.Uri]::UnescapeDataString($relative).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Build-RoleMap {
    $roles = [ordered]@{}
    $agentFiles = Get-ChildItem -LiteralPath $InstallRoot -Recurse -File -Filter *.md | Sort-Object FullName

    foreach ($file in $agentFiles) {
        $frontMatter = Get-FrontMatter -Path $file.FullName
        if (-not $frontMatter -or -not $frontMatter.Contains("name")) {
            continue
        }

        $relativePath = Get-RelativePathCompat -BasePath $InstallRoot -TargetPath $file.FullName
        $category = $relativePath.Split([System.IO.Path]::DirectorySeparatorChar)[0]
        $slug = [System.IO.Path]::GetFileNameWithoutExtension($relativePath)
        $label = [string]$frontMatter["name"]

        $entry = [ordered]@{
            id = $slug
            label = $label
            path = $file.FullName
            category = $category
            mode = Get-DefaultMode -Category $category -Slug $slug
            spawn_as = "worker"
            aliases = @(Get-DefaultAliases -Slug $slug -Label $label)
            auto_route = $false
            may_delegate_children = $false
            recommended_child_depth_limit = 0
            source_relative_path = $relativePath
        }

        $roles[(Convert-ToKey -Slug $slug)] = $entry
    }

    foreach ($profileKey in $autoRouteProfiles.Keys) {
        $profile = $autoRouteProfiles[$profileKey]
        $normalizedRelativePath = Normalize-RelativePath -Path ([string]$profile.relativePath)
        $rolePath = Join-Path $InstallRoot $normalizedRelativePath
        $roles[$profileKey] = [ordered]@{
            id = $profile.id
            label = $profile.label
            path = $rolePath
            category = $normalizedRelativePath.Split([System.IO.Path]::DirectorySeparatorChar)[0]
            mode = $profile.mode
            spawn_as = $profile.spawn_as
            aliases = $profile.aliases
            auto_route = $profile.auto_route
            may_delegate_children = $profile.may_delegate_children
            recommended_child_depth_limit = $profile.recommended_child_depth_limit
            source_relative_path = $normalizedRelativePath
        }
    }

    return $roles
}

function Write-SourceMetadata {
    $commit = ((Invoke-ExternalCommand -Command "git" -Arguments @("-C", $SourceMirrorPath, "rev-parse", "HEAD") -CaptureOutput) -join [Environment]::NewLine).Trim()
    $source = [ordered]@{
        repo = $RepoUrl
        branch = $Branch
        commit = $commit
        synced_at = (Get-Date).ToString("o")
        source_mirror = $SourceMirrorPath
    }
    $json = $source | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath (Join-Path $InstallRoot ".source.json") -Value $json -Encoding UTF8
    return $source
}

function Write-MapFiles {
    param(
        [hashtable]$Roles,
        [hashtable]$SourceInfo
    )

    Ensure-ParentDirectory -Path $MapJsonPath
    Ensure-ParentDirectory -Path $MapMdPath

    $mapObject = [ordered]@{
        version = 1
        source = $SourceInfo
        roles = $Roles
    }

    $mapJson = $mapObject | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $MapJsonPath -Value $mapJson -Encoding UTF8

    $autoRouteRoles = $Roles.GetEnumerator() | Where-Object { $_.Value.auto_route } | Sort-Object Name
    $allRoles = $Roles.GetEnumerator() | Sort-Object Name

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Agency Agent Map")
    $lines.Add("")
    $lines.Add("- Source repo: $($SourceInfo.repo)")
    $lines.Add("- Branch: $($SourceInfo.branch)")
    $lines.Add("- Commit: $($SourceInfo.commit)")
    $lines.Add("- Synced at: $($SourceInfo.synced_at)")
    $lines.Add("- Install root: $InstallRoot")
    $lines.Add("")
    $lines.Add("## Auto-Route Roles")
    $lines.Add("")
    $lines.Add("| Key | Role ID | Mode | Delegates Children | Path |")
    $lines.Add("| --- | --- | --- | --- | --- |")
    foreach ($role in $autoRouteRoles) {
        $lines.Add("| $($role.Name) | $($role.Value.id) | $($role.Value.mode) | $($role.Value.may_delegate_children) | $($role.Value.source_relative_path) |")
    }
    $lines.Add("")
    $lines.Add("## All Roles")
    $lines.Add("")
    $lines.Add("| Key | Role ID | Category | Mode | Auto Route | Path |")
    $lines.Add("| --- | --- | --- | --- | --- | --- |")
    foreach ($role in $allRoles) {
        $lines.Add("| $($role.Name) | $($role.Value.id) | $($role.Value.category) | $($role.Value.mode) | $($role.Value.auto_route) | $($role.Value.source_relative_path) |")
    }

    Set-Content -LiteralPath $MapMdPath -Value $lines -Encoding UTF8
}

Sync-SourceMirror
Install-AgentTemplates
$sourceInfo = Write-SourceMetadata
$roles = Build-RoleMap
Write-MapFiles -Roles $roles -SourceInfo $sourceInfo

Write-Output "Agency agents synchronized."
Write-Output "Templates: $InstallRoot"
Write-Output "Registry:  $MapJsonPath"
Write-Output "Index:     $MapMdPath"
