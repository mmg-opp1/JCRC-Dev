<#
/**
 * @description PORTABLE, drop-in full-org metadata retrieval. Copy this entire
 *              "RetrieveSFLocal" folder into the root of any local repo (or any
 *              empty folder) and run this script to pull a complete local mirror
 *              of a Salesforce org's metadata into a single, unified SFDX source
 *              tree (the project's default package directory, e.g.
 *              force-app/main/default).
 *
 *              Works against ANY org - production, sandbox, scratch, packaging
 *              (namespaced) - regardless of which managed packages, standard
 *              objects, or custom objects it contains. See README.md in this
 *              folder for setup, usage, and troubleshooting.
 *
 *              HOW IT WORKS:
 *                - DISCOVERS the org's metadata types at runtime via
 *                  describeMetadata (no hand-maintained type list).
 *                - NEVER uses wildcards (some orgs do not return namespaced or even
 *                  standard members from a wildcard retrieve). Every member is
 *                  enumerated by name via listMetadata.
 *                - LAYER 1: every customizable object (standard + custom + managed)
 *                  by name from EntityDefinition, so additive (non-namespaced)
 *                  fields on managed objects are captured alongside them.
 *                - LAYER 2: every other top-level type, filtered (by default) to
 *                  members you own (non-namespaced, plus the org's OWN namespace);
 *                  external managed-package components are excluded. Use
 *                  -IncludeManaged to keep them too.
 *                - LAYER 3: folder-based metadata (Email Templates, Reports,
 *                  Dashboards, Documents) via two-pass folder+item enumeration.
 *                - RESILIENT: tries one combined retrieve, then falls back to
 *                  per-type retrieves so one bad type cannot abort the whole run.
 *                - SELF-CONTAINED: writes its generated manifests inside this
 *                  folder, and scaffolds a minimal sfdx-project.json + force-app/
 *                  if the target folder is not already an SFDX project.
 *
 * @author Jason Ott
 * @created 2026-06-17
 *
 * Change Log:
 * -----------
 * 2026-06-17 - Jason Ott - Portable distributable copy of scripts/Retrieve-FullOrg.ps1:
 *                          self-contained manifest paths + SFDX project scaffolding.
 * 2026-06-18 - Jason Ott - Fixed abort on Windows PowerShell 5.1. Under
 *                          $ErrorActionPreference='Stop', the CLI's "update
 *                          available" stderr notice was upgraded to a terminating
 *                          NativeCommandError on every sf call - even with 2>$null /
 *                          2>&1 - aborting the run at the describe step. Added an
 *                          Invoke-Sf wrapper that runs each CLI call under
 *                          'Continue' and discards stderr, returning only clean
 *                          stdout (JSON); routed all sf calls through it.
 *
 * Usage:
 *   ./Retrieve-FullOrg.ps1 -OrgAlias MyOrg
 *   ./Retrieve-FullOrg.ps1                       # uses default org from sf config
 *   ./Retrieve-FullOrg.ps1 -OrgAlias MyOrg -IncludeManaged
 *   ./Retrieve-FullOrg.ps1 -ManifestOnly         # build manifest, no retrieve
 *   ./Retrieve-FullOrg.ps1 -OnlyTypes Flow,PermissionSet
 *   ./Retrieve-FullOrg.ps1 -ExcludeTypes ConnectedApp,CustomObjectTranslation
 */
#>
[CmdletBinding()]
param(
    [string]   $OrgAlias     = "",     # alias/username; defaults to sf config target-org
    [string]   $ApiVersion   = "",     # defaults to sfdx-project sourceApiVersion, else 62.0
    [string]   $ProjectRoot  = "",     # defaults to the parent of this folder
    [switch]   $IncludeManaged,        # keep external managed-package members too
    [string[]] $OnlyTypes    = @(),    # restrict to these top-level types
    [string[]] $ExcludeTypes = @(),    # skip these top-level types
    [switch]   $ManifestOnly           # build manifest, skip the retrieve
)

$ErrorActionPreference = 'Stop'
$script:Warnings = New-Object System.Collections.Generic.List[string]

# Folder-based item type -> its folder metadata type (stable Salesforce mapping).
$FolderTypeMap = @{
    'EmailTemplate' = 'EmailFolder'
    'Report'        = 'ReportFolder'
    'Dashboard'     = 'DashboardFolder'
    'Document'      = 'DocumentFolder'
}

# -------------------------------------------------------------------------
# Preflight: resolve this tool's folder, the target project root, org + version.
# -------------------------------------------------------------------------
$ToolDir = if ($PSScriptRoot) { $PSScriptRoot }
           elseif ($PSCommandPath) { Split-Path $PSCommandPath -Parent }
           else { Split-Path $MyInvocation.MyCommand.Definition -Parent }
if (-not $ProjectRoot) { $ProjectRoot = Split-Path $ToolDir -Parent }
if (-not $ProjectRoot -or -not (Test-Path $ProjectRoot)) {
    throw "Could not resolve ProjectRoot. Pass -ProjectRoot explicitly."
}
Set-Location $ProjectRoot

# Verify the Salesforce CLI is available.
if (-not (Get-Command sf -ErrorAction SilentlyContinue)) {
    throw "Salesforce CLI ('sf') not found on PATH. Install it: https://developer.salesforce.com/tools/salesforcecli"
}

# Invoke the Salesforce CLI and return its stdout as a single string.
#
# WHY THIS WRAPPER EXISTS: the CLI writes notices (e.g. "update available") to
# stderr on every call. Under $ErrorActionPreference='Stop' (set above), Windows
# PowerShell 5.1 upgrades ANY native-command stderr write into a TERMINATING
# NativeCommandError - even when stderr is redirected to $null - which aborts the
# whole script. We isolate each CLI call under 'Continue' and discard stderr, so
# only clean stdout (JSON) is returned; callers still parse that JSON under the
# script's 'Stop'. Pass CLI args exactly as you would to 'sf' (they collect into
# the automatic $args and are splatted through), e.g. Invoke-Sf org list metadata.
function Invoke-Sf {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        return (& sf @args 2>$null | Out-String)
    } finally {
        $ErrorActionPreference = $prev
    }
}

# Scaffold a minimal SFDX project if the target folder isn't one already, so this
# tool can be dropped into ANY folder and still retrieve.
$projFile = Join-Path $ProjectRoot 'sfdx-project.json'
if (-not (Test-Path $projFile)) {
    Write-Host "No sfdx-project.json at $ProjectRoot - scaffolding a minimal SFDX project..."
    $apiForScaffold = if ($ApiVersion) { $ApiVersion } else { '62.0' }
    $projName = (Split-Path $ProjectRoot -Leaf) -replace '[^A-Za-z0-9_-]', '_'
    $scaffoldJson = @"
{
  "packageDirectories": [
    { "path": "force-app", "default": true }
  ],
  "namespace": "",
  "sourceApiVersion": "$apiForScaffold",
  "name": "$projName"
}
"@
    $scaffoldJson | Out-File $projFile -Encoding utf8
    New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot 'force-app') | Out-Null
    Write-Host "  Created sfdx-project.json and force-app/"
}
$proj = Get-Content $projFile -Raw | ConvertFrom-Json

# Default package directory (where source-format retrieves land).
$defaultPkgDir = (@($proj.packageDirectories) | Where-Object { $_.default } | Select-Object -First 1).path
if (-not $defaultPkgDir) { $defaultPkgDir = (@($proj.packageDirectories) | Select-Object -First 1).path }
if (-not $defaultPkgDir) { $defaultPkgDir = 'force-app' }

# Resolve org alias: fall back to the configured default target-org.
if (-not $OrgAlias) {
    try {
        $cfg = Invoke-Sf config get target-org --json | ConvertFrom-Json
        $OrgAlias = @($cfg.result)[0].value
    } catch { }
    if (-not $OrgAlias) {
        throw "No -OrgAlias given and no default target-org configured. Pass -OrgAlias, or run: sf config set target-org <alias>"
    }
}

# Resolve API version from the project, else a conservative default.
if (-not $ApiVersion) {
    if ($proj.sourceApiVersion) { $ApiVersion = "$($proj.sourceApiVersion)" } else { $ApiVersion = '62.0' }
}

$started = Get-Date
Write-Host "==================================================================="
Write-Host " Full-org retrieve -> $defaultPkgDir"
Write-Host " org: $OrgAlias  |  api: $ApiVersion  |  includeManaged: $([bool]$IncludeManaged)  |  $(Get-Date -Format s)"
Write-Host "==================================================================="

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

# Keep a member if it has no namespace, or (for packaging orgs) it is in the org's
# OWN namespace. External managed-package members are dropped unless -IncludeManaged.
function Test-Owned {
    param($Record, [string]$OwnNamespace)
    if ($IncludeManaged) { return $true }
    $ns = $Record.namespacePrefix
    return ((-not $ns) -or ($OwnNamespace -and ($ns -eq $OwnNamespace)))
}

# Enumerate a top-level metadata type's owned members via listMetadata.
function Get-OwnedMembers {
    param([string]$Type, [string]$OwnNamespace)
    try {
        $raw = Invoke-Sf org list metadata -m $Type -o $OrgAlias --api-version $ApiVersion --json
        if (-not $raw.Trim()) { return @() }
        $j = $raw | ConvertFrom-Json
        if ($j.status -ne 0) { $script:Warnings.Add("listMetadata $Type -> status $($j.status)"); return @() }
        $recs = @($j.result) | Where-Object { $_.fullName }
        $owned = $recs | Where-Object { Test-Owned -Record $_ -OwnNamespace $OwnNamespace }
        return @($owned | Select-Object -ExpandProperty fullName -Unique | Sort-Object)
    } catch {
        $script:Warnings.Add("listMetadata $Type failed: $($_.Exception.Message)")
        return @()
    }
}

# Enumerate a folder-based type: owned folders, then owned items in each.
function Get-FolderedMembers {
    param([string]$ItemType, [string]$FolderType, [string]$OwnNamespace)
    $members = New-Object System.Collections.Generic.List[string]
    try {
        $fraw = Invoke-Sf org list metadata -m $FolderType -o $OrgAlias --api-version $ApiVersion --json
        if (-not $fraw.Trim()) { return @() }
        $folders = @(($fraw | ConvertFrom-Json).result) |
            Where-Object { $_.fullName -and (Test-Owned -Record $_ -OwnNamespace $OwnNamespace) } |
            Select-Object -ExpandProperty fullName -Unique
        foreach ($folder in $folders) {
            $members.Add($folder)
            try {
                $iraw = Invoke-Sf org list metadata -m $ItemType --folder $folder -o $OrgAlias --api-version $ApiVersion --json
                if ($iraw.Trim()) {
                    $items = @(($iraw | ConvertFrom-Json).result) |
                        Where-Object { $_.fullName -and (Test-Owned -Record $_ -OwnNamespace $OwnNamespace) } |
                        Select-Object -ExpandProperty fullName -Unique
                    foreach ($it in $items) { $members.Add($it) }
                }
            } catch { }
        }
    } catch {
        $script:Warnings.Add("folder enumeration $ItemType failed: $($_.Exception.Message)")
        return @()
    }
    return @($members | Sort-Object -Unique)
}

# Write an explicit-member package manifest from an ordered type->members map.
function Write-Manifest {
    param($Types, [string]$Path)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<Package xmlns="http://soap.sforce.com/2006/04/metadata">')
    foreach ($type in $Types.Keys) {
        [void]$sb.AppendLine('    <types>')
        foreach ($member in $Types[$type]) {
            $safe = $member -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
            [void]$sb.AppendLine("        <members>$safe</members>")
        }
        [void]$sb.AppendLine("        <name>$type</name>")
        [void]$sb.AppendLine('    </types>')
    }
    [void]$sb.AppendLine("    <version>$ApiVersion</version>")
    [void]$sb.AppendLine('</Package>')
    $sb.ToString() | Out-File $Path -Encoding utf8
}

# Run a retrieve for a manifest. Returns {Ok, Count, Message}.
function Invoke-RetrieveManifest {
    param([string]$ManifestPath)
    $raw = Invoke-Sf project retrieve start -x $ManifestPath -o $OrgAlias --api-version $ApiVersion --json
    try {
        $j = $raw | ConvertFrom-Json
        if ($j.status -eq 0) {
            $n = (@($j.result.files) | Where-Object { $_.fullName } | Measure-Object).Count
            return [pscustomobject]@{ Ok = $true;  Count = $n; Message = "" }
        }
        return [pscustomobject]@{ Ok = $false; Count = 0; Message = "$($j.message)".Trim() }
    } catch {
        return [pscustomobject]@{ Ok = $false; Count = 0; Message = $raw.Substring(0, [Math]::Min(300, $raw.Length)) }
    }
}

# -------------------------------------------------------------------------
# Discover the org's metadata types (also acts as the org reachability check).
# -------------------------------------------------------------------------
Write-Host "`n### Discovering metadata types (describeMetadata) ###"
$descRaw = Invoke-Sf org list metadata-types -o $OrgAlias --api-version $ApiVersion --json
$desc = $null
try { $desc = $descRaw | ConvertFrom-Json } catch { }
if (-not $desc -or $desc.status -ne 0 -or -not $desc.result.metadataObjects) {
    throw "Could not describe metadata for org '$OrgAlias'. Is it authenticated? Try:`n    sf org login web --alias $OrgAlias`n`n$descRaw"
}
$allTypes = @($desc.result.metadataObjects)
$ownNs    = "$($desc.result.organizationNamespace)"
Write-Host "Org exposes $($allTypes.Count) metadata types. Org namespace: '$ownNs'"

# Classify discovered types.
$childTypes      = @($allTypes | Where-Object { $_.childXmlNames } | ForEach-Object { $_.childXmlNames }) | Sort-Object -Unique
$folderItemTypes = @($allTypes | Where-Object { $_.inFolder } | Select-Object -ExpandProperty xmlName | Sort-Object -Unique)
$folderTypeNames = $FolderTypeMap.Values

$skip = @('CustomObject') + $childTypes + $folderTypeNames + $folderItemTypes
$regularTypes = @($allTypes |
    Where-Object { -not $_.inFolder } |
    Select-Object -ExpandProperty xmlName |
    Where-Object { $skip -notcontains $_ } |
    Sort-Object -Unique)

if ($OnlyTypes.Count)    { $regularTypes = @($regularTypes | Where-Object { $OnlyTypes -contains $_ });    $folderItemTypes = @($folderItemTypes | Where-Object { $OnlyTypes -contains $_ }) }
if ($ExcludeTypes.Count) { $regularTypes = @($regularTypes | Where-Object { $ExcludeTypes -notcontains $_ }); $folderItemTypes = @($folderItemTypes | Where-Object { $ExcludeTypes -notcontains $_ }) }
$includeObjects = (-not $OnlyTypes.Count) -or ($OnlyTypes -contains 'CustomObject')
if ($ExcludeTypes -contains 'CustomObject') { $includeObjects = $false }

$typeMembers = [ordered]@{}

# -------------------------------------------------------------------------
# LAYER 1 - Objects (standard + custom + managed) by explicit name.
# -------------------------------------------------------------------------
if ($includeObjects) {
    Write-Host "`n### LAYER 1: Objects (standard + custom + managed) ###"
    $soql = "SELECT QualifiedApiName FROM EntityDefinition " +
            "WHERE IsCustomizable = true AND KeyPrefix != null ORDER BY QualifiedApiName"
    try {
        $ed = Invoke-Sf data query -o $OrgAlias -q $soql --json | ConvertFrom-Json
        $objects = @($ed.result.records | Select-Object -ExpandProperty QualifiedApiName -Unique | Sort-Object)
        if ($objects.Count) { $typeMembers['CustomObject'] = $objects }
        Write-Host "Found $($objects.Count) customizable objects."
    } catch {
        $script:Warnings.Add("EntityDefinition object query failed: $($_.Exception.Message)")
        Write-Host "    WARN: object query failed - see warnings."
    }
}

# -------------------------------------------------------------------------
# LAYER 2 - Every other top-level type (namespace-filtered).
# -------------------------------------------------------------------------
Write-Host "`n### LAYER 2: Regular types ($($regularTypes.Count) discovered) ###"
$emptyCount = 0
foreach ($t in $regularTypes) {
    $m = Get-OwnedMembers -Type $t -OwnNamespace $ownNs
    if ($m.Count -gt 0) {
        $typeMembers[$t] = $m
        Write-Host ("    {0,-32} {1,5}" -f $t, $m.Count)
    } else { $emptyCount++ }
}
Write-Host "    ($emptyCount types had no owned members)"

# -------------------------------------------------------------------------
# LAYER 3 - Folder-based metadata.
# -------------------------------------------------------------------------
if ($folderItemTypes.Count) {
    Write-Host "`n### LAYER 3: Folder-based metadata ###"
    foreach ($itemType in $folderItemTypes) {
        $folderType = $FolderTypeMap[$itemType]
        if (-not $folderType) { $script:Warnings.Add("No folder-type mapping for inFolder type '$itemType' - skipped"); continue }
        $m = Get-FolderedMembers -ItemType $itemType -FolderType $folderType -OwnNamespace $ownNs
        if ($m.Count -gt 0) {
            $typeMembers[$itemType] = $m
            Write-Host ("    {0,-32} {1,5} (folders + items)" -f $itemType, $m.Count)
        } else {
            Write-Host ("    {0,-32} {1,5}" -f $itemType, "-")
        }
    }
}

# -------------------------------------------------------------------------
# Build the comprehensive, explicit-member manifest (kept inside this folder).
# -------------------------------------------------------------------------
if ($typeMembers.Keys.Count -eq 0) { throw "Nothing to retrieve - no owned members enumerated. Check org/scoping switches." }
$manifest = Join-Path $ToolDir "full-org.generated.xml"
Write-Manifest -Types $typeMembers -Path $manifest
$totalMembers = ($typeMembers.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
Write-Host "`nWrote manifest: $manifest"
Write-Host "Manifest contains $($typeMembers.Keys.Count) types / $totalMembers explicit members."

if ($ManifestOnly) {
    if ($script:Warnings.Count) { Write-Host "`nWarnings:`n  - $([string]::Join("`n  - ", $script:Warnings))" }
    Write-Host "`n-ManifestOnly set; skipping retrieve."
    return
}

# -------------------------------------------------------------------------
# Retrieve. Fast path = one combined retrieve; on failure, per-type fallback.
# -------------------------------------------------------------------------
Write-Host "`n### Retrieving into $defaultPkgDir ###"
$res = Invoke-RetrieveManifest -ManifestPath $manifest
if ($res.Ok) {
    Write-Host "    OK: $($res.Count) components retrieved (single pass)."
} else {
    Write-Host "    Combined retrieve failed: $($res.Message)"
    Write-Host "    Falling back to resilient per-type retrieves..."
    $tmp = Join-Path $ToolDir "_type.generated.xml"
    $okTotal = 0; $failed = @()
    foreach ($type in $typeMembers.Keys) {
        $one = [ordered]@{}; $one[$type] = $typeMembers[$type]
        Write-Manifest -Types $one -Path $tmp
        $r = Invoke-RetrieveManifest -ManifestPath $tmp
        if ($r.Ok) { $okTotal += $r.Count; Write-Host ("    OK    {0,-30} {1}" -f $type, $r.Count) }
        else       { $failed += $type;     Write-Host ("    FAIL  {0,-30} {1}" -f $type, $r.Message) }
    }
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Write-Host "`n    Per-type retrieve: $okTotal components OK."
    if ($failed.Count) { Write-Host "    Failed types (re-run with -ExcludeTypes to skip, or investigate): $($failed -join ', ')" }
}

# -------------------------------------------------------------------------
# SUMMARY
# -------------------------------------------------------------------------
Write-Host "`n==================================================================="
Write-Host " SUMMARY  |  elapsed: $([int]((Get-Date) - $started).TotalMinutes) min"
Write-Host "==================================================================="
$base = Join-Path $ProjectRoot ($defaultPkgDir + "\main\default")
if (-not (Test-Path $base)) { $base = Join-Path $ProjectRoot $defaultPkgDir }
if (Test-Path $base) {
    Get-ChildItem $base -Directory | ForEach-Object {
        $count = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
        [PSCustomObject]@{ Folder = $_.Name; Files = $count }
    } | Sort-Object Files -Descending | Format-Table -AutoSize | Out-Host
}
if ($script:Warnings.Count) {
    Write-Host "Warnings ($($script:Warnings.Count)):"
    $script:Warnings | ForEach-Object { Write-Host "  - $_" }
}
