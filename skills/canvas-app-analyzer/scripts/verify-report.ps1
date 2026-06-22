<#
.SYNOPSIS
    Reconciles a finished narrative report against mechanical-findings.json, emitting
    a compact gap JSON so the model only spends tokens fixing real gaps.

.DESCRIPTION
    Reads the mechanical-findings.json produced by analyze-canvas.ps1 and checks that
    every High/Medium deterministic finding id AND every lead id appears (word-boundary
    match) somewhere in the narrative report .md.

    Low-severity findings are covered by the script-generated enumeration.md (D2) and
    are NOT required in the narrative, so they are never reported as "missing".

    Always exits 0; on any error prints { "complete": false, "error": "<msg>" }.

.PARAMETER ReportPath
    Path to the narrative report Markdown file to check.

.PARAMETER FindingsPath
    Path to the mechanical-findings.json produced by analyze-canvas.ps1.

.OUTPUTS
    Compact JSON to stdout:
      { "complete": <bool>, "missing": [<ids>], "unaddressedLeads": [<ids>] }
    or on error:
      { "complete": false, "error": "<message>" }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ReportPath,
    [Parameter(Mandatory)][string]$FindingsPath
)

$ErrorActionPreference = 'Stop'

try {
    $report = Get-Content -LiteralPath $ReportPath -Raw
    $mech   = Get-Content -LiteralPath $FindingsPath -Raw | ConvertFrom-Json

    $missing     = @()
    $unaddressed = @()

    # High/Medium deterministic findings must appear in the narrative
    foreach ($f in $mech.deterministicFindings) {
        if ($f.severity -in 'High', 'Medium') {
            $pattern = '(?<![\w-])' + [regex]::Escape($f.id) + '(?![\w-])'
            if ($report -notmatch $pattern) {
                $missing += $f.id
            }
        }
    }

    # All leads must appear in the narrative
    foreach ($l in $mech.leads) {
        $pattern = '(?<![\w-])' + [regex]::Escape($l.id) + '(?![\w-])'
        if ($report -notmatch $pattern) {
            $unaddressed += $l.id
        }
    }

    $complete = ($missing.Count -eq 0) -and ($unaddressed.Count -eq 0)

    # Force arrays so ConvertTo-Json never collapses a single-element array to a scalar
    [ordered]@{
        complete         = $complete
        missing          = @($missing)
        unaddressedLeads = @($unaddressed)
    } | ConvertTo-Json -Compress

    exit 0
} catch {
    @{ complete = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
    exit 0
}
