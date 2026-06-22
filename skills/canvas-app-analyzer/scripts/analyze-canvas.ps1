<#
.SYNOPSIS
    Canvas App Analyzer - deterministic extraction + inventory + mechanical findings.

.DESCRIPTION
    READ-ONLY helper for the canvas-app-analyzer Copilot CLI skill. It does the
    mechanical, reproducible half of the analysis so the model can spend its budget
    on judgment. It never modifies the input app and never writes back into any .msapp.

    Pipeline (current Microsoft guidance - no `pac`, no deprecated tooling):
      1. Treat the input .zip / .msapp as a plain ZIP archive and extract it.
      2. Recursively (case-insensitively) find *.msapp anywhere in the tree - raw
         solution exports and `pac solution unpack` layouts place them differently,
         so NO path is hardcoded.
      3. A .msapp is itself a ZIP - extract it and read ONLY \Src\*.pa.yaml (the one
         active source format). The sibling .json is explicitly unstable; we ignore it
         for source code (we read \DataSources\*.json only to resolve connector TYPE).
      4. Branch on app count: 0 -> stop, 1 -> proceed, many -> list for the model to
         prompt. If a selected app has no \Src\*.pa.yaml it predates the YAML format
         -> stop with an actionable message.

    Extraction uses [System.IO.Compression.ZipFile] rather than Expand-Archive: it is
    the same dependency-free, `pac`-free "plain unzip" the spec calls for, but unlike
    Expand-Archive (PS 5.1) it accepts the non-.zip ".msapp" extension directly without
    a rename. No external modules are required.

.PARAMETER Path
    Path to the solution .zip OR a bare .msapp.

.PARAMETER AppName
    When several Canvas apps are found, the schema/display name of the one to analyze.
    Omit on the first run; the script lists the apps and the model re-invokes with this.

.PARAMETER OutputRoot
    Where per-app output folders are created. Default: ./canvas-analysis

.OUTPUTS
    Always prints a single status JSON object to stdout (the model's control-flow signal).
    On success also writes, under <OutputRoot>/<AppName>/ :
      src/                         persisted \Src\*.pa.yaml (browsable + citation targets)
      .analysis/index.json         inventory the model reads first
      .analysis/index.md           compact human-browsable orientation digest
      .analysis/mechanical-findings.json   deterministic findings + judgment "leads"
      .analysis/status.json        copy of the stdout status

.NOTES
    Parsing is intentionally line/indent-based, not a full YAML parse: PowerShell 5.1
    ships no YAML cmdlet and adding a module would break the "native only" constraint.
    The model always re-reads the cited .pa.yaml line to confirm before it reports -
    so heuristic parsing produces *leads*, never unverified findings.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Path,

    [Parameter(Position = 1)]
    [string] $AppName,

    [string] $OutputRoot = (Join-Path (Get-Location) 'canvas-analysis')
)

# No Set-StrictMode: this script does deliberate dynamic property access against
# arbitrary .pa.yaml / .json shapes; strict mode would throw on absent members.
# Robustness comes from the top-level try/catch, which always emits a status JSON.
$ErrorActionPreference = 'Stop'
$work = $null

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
function Write-Status {
    param([hashtable] $Obj, [string] $StatusFilePath)
    $json = $Obj | ConvertTo-Json -Depth 12
    if ($StatusFilePath) {
        $dir = Split-Path -Parent $StatusFilePath
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $json | Out-File -FilePath $StatusFilePath -Encoding utf8
    }
    Write-Output $json
}

function New-TempDir {
    $name = 'caa_' + ([System.Guid]::NewGuid().ToString('N'))
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) $name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Expand-ZipArchive {
    # Plain-archive extraction, dependency-free, accepts any extension (.zip or .msapp).
    param([string] $ArchivePath, [string] $Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
    [System.IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path $ArchivePath).Path, $Destination)
}

# ---------------------------------------------------------------------------
# Threshold constants — each seeded from a CAA_<UPPER_SNAKE> env var.
# _Thr returns the env value as a number when it matches ^\d+(\.\d+)?$,
# otherwise returns the hard-coded default.  Override examples:
#   $env:CAA_LONG_FORMULA_BYTES = '300'   (tighten in CI)
#   $env:CAA_NEAR_DUP_RATIO     = '0.85'
# ---------------------------------------------------------------------------
function _Thr([string]$name, [double]$default) {
    $v = [Environment]::GetEnvironmentVariable("CAA_$name")
    if ($v -and $v -match '^\d+(\.\d+)?$') { return [double]$v }
    return $default
}

$T_LongFormulaBytes   = _Thr 'LONG_FORMULA_BYTES'   500   # flag single-property formulas wider than this many bytes
$T_DeepIfDepth        = _Thr 'DEEP_IF_DEPTH'           4   # nested If/Switch depth that triggers a complexity lead
$T_GodScreenControls  = _Thr 'GOD_SCREEN_CONTROLS'   40   # control count above which a screen is flagged as a god-screen
$T_GodScreenBytes     = _Thr 'GOD_SCREEN_BYTES'    20000   # total formula-byte count above which a screen is flagged
$T_ControlTreeDepth   = _Thr 'CONTROL_TREE_DEPTH'      5   # nesting depth at which a control-tree depth lead fires
$T_RepeatedLiteralMin = _Thr 'REPEATED_LITERAL_MIN'    3   # minimum repetition count to flag a repeated string literal
$T_NearDupRatio       = _Thr 'NEAR_DUP_RATIO'       0.90   # Jaccard similarity ratio above which formulas are near-duplicates
$T_NearDupMinLen      = _Thr 'NEAR_DUP_MIN_LEN'       60   # minimum formula length (chars) before near-dup comparison runs
$T_GlobalOveruse      = _Thr 'GLOBAL_OVERUSE'         20   # number of global variables above which a global-overuse lead fires

# ---------------------------------------------------------------------------
# Connector type mapping (best-effort; the model refines via \DataSources + leads)
# ---------------------------------------------------------------------------
function Resolve-Connector {
    param([string] $Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return 'unknown' }
    $r = $Raw.ToLowerInvariant()
    if ($r -match 'sharepoint')            { return 'SharePoint' }
    if ($r -match 'commondataservice|dataverse|cds') { return 'Dataverse' }
    if ($r -match 'sql')                   { return 'SQL Server' }
    if ($r -match 'excel')                 { return 'Excel' }
    if ($r -match 'office365users|office365groups') { return 'Office 365' }
    return $Raw
}

# ---------------------------------------------------------------------------
# Formula tokenizer: split a Power Fx formula into code spans vs string-literal spans.
# Power Fx strings are double-quoted; "" inside a literal is an escaped quote character.
# ---------------------------------------------------------------------------
function Split-FormulaSpans {
    param([string]$Text)
    if ($null -eq $Text -or $Text.Length -eq 0) { return [pscustomobject]@{ Code=''; Strings=@() } }
    $code    = New-Object System.Text.StringBuilder
    $strings = New-Object System.Collections.ArrayList
    $i = 0; $n = $Text.Length
    while ($i -lt $n) {
        $ch = $Text[$i]
        if ($ch -eq '"') {
            $startIndex = $i   # save position of the opening quote
            $i++; $lit = New-Object System.Text.StringBuilder
            while ($i -lt $n) {
                if ($Text[$i] -eq '"') {
                    if ($i + 1 -lt $n -and $Text[$i + 1] -eq '"') {
                        [void]$lit.Append('"'); $i += 2; continue
                    }
                    $i++; break
                }
                [void]$lit.Append($Text[$i]); $i++
            }
            [void]$strings.Add($lit.ToString())
            # Replace the entire "..." token with spaces equal to consumed input length,
            # preserving column positions for all inputs (including "" escapes and unterminated literals).
            [void]$code.Append(' ' * ($i - $startIndex))
        } else {
            [void]$code.Append($ch); $i++
        }
    }
    [pscustomobject]@{ Code = $code.ToString(); Strings = @($strings) }
}

# ---------------------------------------------------------------------------
# Known control type words (for default-name detection + prefix table)
# Default names look like "<TypeWord><digits>" e.g. Gallery3, Button1, Screen2.
# ---------------------------------------------------------------------------
$ControlTypeWords = @(
    'Screen','Button','Gallery','Label','TextInput','Text','Icon','Image','Rectangle',
    'Circle','Toggle','Slider','Checkbox','CheckBox','Radio','Dropdown','DropDown','ComboBox',
    'Combobox','DatePicker','DataTable','Form','EditForm','DisplayForm','Card','Container',
    'GroupContainer','Group','Timer','Camera','Barcode','PenInput','Rating','RichTextEditor',
    'HtmlText','Video','Audio','Microphone','PowerBITile','Chart','ColumnChart','LineChart',
    'PieChart','ListBox','Shape','Component','Header','Badge','Link','Table','Tab','TabList'
)
$defaultNameRegex = '^(' + ($ControlTypeWords -join '|') + ')_?\d+$'

# Variable / collection naming prefixes (from coding-standards reference)
# loc = context, gbl = global, col = collection, scp = scope (With)

# Functions that are non-delegable on every connector (high-confidence delegation leads)
$alwaysLocalFns = @('FirstN','LastN','Last','Choices','Concat','GroupBy','Ungroup')

# ---------------------------------------------------------------------------
# Finding / Lead constructors + ID stamper (Task 6 / D3)
# ---------------------------------------------------------------------------
function New-Finding {
    param(
        [string]$Prefix,
        [string]$Type,
        [string]$Category,
        [string]$Severity,
        [string]$Confidence,
        $Location,
        [string]$Evidence,
        [string]$Message,
        [string]$SortKey,
        [string]$Tier = 'enumeration',
        [string]$Citation = $null,
        $Verdict = $null
    )
    [pscustomobject]@{
        id         = $null
        prefix     = $Prefix
        type       = $Type
        category   = $Category
        severity   = $Severity
        confidence = $Confidence
        tier       = $Tier
        citation   = $Citation
        verdict    = $Verdict
        location   = $Location
        evidence   = $Evidence
        message    = $Message
        sortKey    = [string]$SortKey
    }
}

function New-Lead {
    param([string]$Kind,[string]$Category,$Screen,$Control,$Property,[string]$File,[string]$Line,[string]$Snippet,[string]$Hint)
    [pscustomobject]@{
        id       = $null
        prefix   = 'L'
        category = $Category
        kind     = $Kind
        screen   = $Screen
        control  = $Control
        property = $Property
        file     = $File
        line     = $Line
        snippet  = $Snippet
        hint     = $Hint
    }
}

function Stamp-Ids {
    param(
        [System.Collections.IEnumerable]$Findings,
        [System.Collections.IEnumerable]$Leads
    )
    foreach ($grp in ($Findings | Group-Object prefix)) {
        $i = 0
        foreach ($f in ($grp.Group | Sort-Object sortKey)) {
            $i++
            $f.id = ('{0}-{1:D2}' -f $grp.Name, $i)
        }
    }
    $j = 0
    foreach ($l in ($Leads | Sort-Object @{e={$_.file}},@{e={ if ($null -eq $_.line) { 0 } else { [int]$_.line } }},@{e={$_.kind}})) {
        $j++
        $l.id = ('L-{0:D2}' -f $j)
    }
}

try {
    # Self-test shim: invoked as analyze-canvas.ps1 '__spans' with formula in
    # $env:CAA_SPANS_FORMULA (env var avoids PowerShell child-process quoting issues
    # for formulas that contain double-quotes). Falls back to $AppName for simple cases.
    # Prints Split-FormulaSpans result as compact JSON and exits 0.
    # Normal analysis runs ($Path is a real file path) are completely unaffected.
    if ($Path -eq '__spans') {
        $formula = if ($env:CAA_SPANS_FORMULA -ne $null) { $env:CAA_SPANS_FORMULA } else { $AppName }
        (Split-FormulaSpans $formula) | ConvertTo-Json -Compress
        exit 0
    }

    # Self-test shim: invoked as analyze-canvas.ps1 '__thresholds'
    # Prints all resolved $T_* threshold values as compact JSON and exits 0.
    # Normal analysis runs ($Path is a real file path) are completely unaffected.
    if ($Path -eq '__thresholds') {
        [ordered]@{
            T_LongFormulaBytes   = $T_LongFormulaBytes
            T_DeepIfDepth        = $T_DeepIfDepth
            T_GodScreenControls  = $T_GodScreenControls
            T_GodScreenBytes     = $T_GodScreenBytes
            T_ControlTreeDepth   = $T_ControlTreeDepth
            T_RepeatedLiteralMin = $T_RepeatedLiteralMin
            T_NearDupRatio       = $T_NearDupRatio
            T_NearDupMinLen      = $T_NearDupMinLen
            T_GlobalOveruse      = $T_GlobalOveruse
        } | ConvertTo-Json -Compress
        exit 0
    }

    if (-not (Test-Path $Path)) {
        Write-Status -Obj @{ status = 'error'; message = "Input path not found: $Path" }
        exit 0
    }

    $statusFileEarly = Join-Path $OutputRoot '_status.json'

    # --- 1. Extract the outer archive (or treat a bare .msapp as the only app) -------
    $work = New-TempDir
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    $msapps = @()
    if ($ext -eq '.msapp') {
        # Bare .msapp: it IS the single app. Copy into the workspace and use directly.
        $dest = Join-Path $work ([System.IO.Path]::GetFileName($Path))
        Copy-Item -LiteralPath $Path -Destination $dest -Force
        $msapps = @(Get-Item -LiteralPath $dest)
    }
    else {
        $solutionDir = Join-Path $work 'solution'
        Expand-ZipArchive -ArchivePath $Path -Destination $solutionDir
        # Recursive, case-insensitive *.msapp search - robust to raw-export AND
        # pac-solution-unpack (canvasapps/<schema>/) layouts. No hardcoded path.
        $msapps = @(Get-ChildItem -Path $solutionDir -Recurse -File |
                    Where-Object { $_.Extension -ieq '.msapp' })
    }

    # --- App-count branching --------------------------------------------------------
    if ($msapps.Count -eq 0) {
        Write-Status -StatusFilePath $statusFileEarly -Obj @{
            status  = 'no-canvas-app'
            message = 'No Canvas app (.msapp) was found in this archive. It may contain only flows, tables, or other solution components. Nothing to analyze.'
        }
        exit 0
    }

    if ($msapps.Count -gt 1 -and [string]::IsNullOrWhiteSpace($AppName)) {
        $list = @($msapps | ForEach-Object { @{ name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name); file = $_.Name } })
        Write-Status -StatusFilePath $statusFileEarly -Obj @{
            status  = 'multiple-apps'
            message = 'Multiple Canvas apps were found. Ask the user which one to analyze, then re-run with -AppName "<name>".'
            apps    = $list
        }
        exit 0
    }

    # Select the target .msapp
    if ($msapps.Count -gt 1) {
        $chosen = $msapps | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -ieq $AppName } | Select-Object -First 1
        if (-not $chosen) {
            $list = @($msapps | ForEach-Object { @{ name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name); file = $_.Name } })
            Write-Status -StatusFilePath $statusFileEarly -Obj @{
                status  = 'app-not-found'
                message = "No Canvas app named '$AppName' was found. Choose one of the listed apps and re-run with -AppName."
                apps    = $list
            }
            exit 0
        }
    }
    else {
        $chosen = $msapps[0]
    }

    # --- 2/3. Extract the chosen .msapp ---------------------------------------------
    $appExtract = Join-Path $work ('app_' + [System.IO.Path]::GetFileNameWithoutExtension($chosen.Name))
    Expand-ZipArchive -ArchivePath $chosen.FullName -Destination $appExtract

    # Find the \Src folder (case-insensitive) and its *.pa.yaml files.
    $srcDir = Get-ChildItem -Path $appExtract -Recurse -Directory |
              Where-Object { $_.Name -ieq 'Src' } | Select-Object -First 1
    $paFiles = @()
    if ($srcDir) {
        $paFiles = @(Get-ChildItem -Path $srcDir.FullName -Recurse -File |
                     Where-Object { $_.Name -ilike '*.pa.yaml' })
    }

    # --- 6. Legacy preflight: no \Src\*.pa.yaml -> stop loud ------------------------
    if ($paFiles.Count -eq 0) {
        Write-Status -StatusFilePath $statusFileEarly -Obj @{
            status  = 'legacy-no-src'
            message = "This app ('$([System.IO.Path]::GetFileNameWithoutExtension($chosen.Name))') predates the YAML source format (no \Src\*.pa.yaml inside the .msapp). To regenerate it: open the app in Power Apps Studio -> File -> Save as -> This computer, download the new .msapp, and re-run. No analysis of the unstable .json files is performed."
        }
        exit 0
    }

    # Resolve a friendly app name (CanvasManifest.json if present, else file name)
    $displayName = [System.IO.Path]::GetFileNameWithoutExtension($chosen.Name)
    $manifest = Get-ChildItem -Path $appExtract -Recurse -File |
                Where-Object { $_.Name -ieq 'CanvasManifest.json' } | Select-Object -First 1
    if ($manifest) {
        try {
            $mj = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json
            foreach ($prop in 'Name','DisplayName','AppName') {
                if ($mj.PSObject.Properties.Name -contains $prop -and $mj.$prop) { $displayName = [string]$mj.$prop; break }
            }
            if ($mj.PSObject.Properties.Name -contains 'Properties' -and $mj.Properties) {
                if ($mj.Properties.PSObject.Properties.Name -contains 'Name' -and $mj.Properties.Name) { $displayName = [string]$mj.Properties.Name }
            }
        } catch { }
    }
    # Sanitize for a folder name
    $safeName = ($displayName -replace '[\\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = [System.IO.Path]::GetFileNameWithoutExtension($chosen.Name) }

    $appOut    = Join-Path $OutputRoot $safeName
    $srcOut    = Join-Path $appOut 'src'
    $analysisOut = Join-Path $appOut '.analysis'
    foreach ($d in @($appOut, $srcOut, $analysisOut)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }

    # --- Persist the source (lasting asset + citation targets) ----------------------
    foreach ($f in $paFiles) {
        # preserve any Component subfolder relative to \Src
        $rel = $f.FullName.Substring($srcDir.FullName.Length).TrimStart('\','/')
        $target = Join-Path $srcOut $rel
        $tdir = Split-Path -Parent $target
        if ($tdir -and -not (Test-Path $tdir)) { New-Item -ItemType Directory -Path $tdir -Force | Out-Null }
        Copy-Item -LiteralPath $f.FullName -Destination $target -Force
    }

    # ============================================================================
    # PARSE: build a flat list of property-formula records from each .pa.yaml.
    # Each record = { screen, control, property, file, line, text }.
    # Everything else (controls, vars, nav, refs, duplicates, leads) derives from it.
    # ============================================================================
    $formulas  = New-Object System.Collections.ArrayList   # property formula records
    $controls  = New-Object System.Collections.ArrayList   # {name,type,screen,file,line}
    $compFiles = @{}                                        # component file -> true

    function Get-Indent { param([string] $Line) ($Line -replace '^( *).*$', '$1').Length }

    foreach ($f in $paFiles) {
        $lines = Get-Content -LiteralPath $f.FullName
        # Content/structure signal: a component-definition file declares a CanvasComponent node
        # (ComponentDefinitions:, "Type: CanvasComponent", or a top-level CustomProperties block).
        # Tolerate BOTH \Component\ and \Components\ folder spellings as a secondary signal.
        $headText = ($lines | Select-Object -First 60) -join "`n"
        $isComponent = ($headText -imatch '(?m)^\s*ComponentDefinitions\s*:') `
            -or ($headText -imatch '(?im)Type\s*:\s*CanvasComponent') `
            -or ($f.FullName -imatch '[\\/]Components?[\\/]')
        $isApp = $f.Name -ieq 'App.pa.yaml'
        # Logical "screen" label = file stem (docs: one [ScreenName].pa.yaml per screen).
        $screenLabel = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) -replace '\.pa$',''
        if ($isApp) { $screenLabel = 'App' }
        $relPath = (Join-Path 'src' ($f.FullName.Substring($srcDir.FullName.Length).TrimStart('\','/'))) -replace '\\','/'
        if ($isComponent) { $compFiles[$screenLabel] = $true }
        $n = $lines.Count

        # Track the current control context via an indent stack of {indent,name}.
        $stack = New-Object System.Collections.Stack
        # Control-only stack: tracks only control nodes (not structural YAML nodes like
        # Children:/Properties:/Screens:). Used to compute nesting depth and ancestors.
        $ctrlStack = New-Object System.Collections.Stack
        $curControl = $null

        for ($i = 0; $i -lt $n; $i++) {
            $line = $lines[$i]
            if ($line -match '^\s*$') { continue }
            $indent = Get-Indent $line
            $trim = $line.Trim()

            # Pop stack entries that are at >= current indent (we've left their scope)
            while ($stack.Count -gt 0 -and $stack.Peek().Indent -ge $indent) { [void]$stack.Pop() }
            # Also pop the control-only stack for any controls whose scope we've left
            while ($ctrlStack.Count -gt 0 -and $ctrlStack.Peek().Indent -ge $indent) { [void]$ctrlStack.Pop() }

            # Control declaration: a node key whose next meaningful child is "Control:"
            # Node key forms:  "- Name:"  or  "Name:"
            if ($trim -match '^-?\s*([A-Za-z_][\w]*):\s*$') {
                $key = $Matches[1]
                # A node is a control only if its IMMEDIATE next deeper line is "Control:"
                # (in pa.yaml v3 the Control: key is always a control's first child). Looking
                # only at the first child avoids mistaking Screens/Children/screen names --
                # whose deeper descendants include a Control: -- for controls.
                $isCtrl = $false; $ctrlType = $null
                for ($j = $i + 1; $j -lt $n; $j++) {
                    if ($lines[$j] -match '^\s*$') { continue }
                    $jIndent = Get-Indent $lines[$j]
                    if ($jIndent -le $indent) { break }          # no deeper child at all
                    if ($lines[$j].Trim() -match '^Control:\s*(.+)$') { $isCtrl = $true; $ctrlType = $Matches[1].Trim() }
                    break                                         # only the first deeper line counts
                }
                $stack.Push([pscustomobject]@{ Indent = $indent; Name = $key })
                if ($isCtrl) {
                    # Depth = number of control ancestors + 1 (top-level control = 1)
                    $depth = $ctrlStack.Count + 1
                    # Ancestors: root-first array of control names (Stack.ToArray() is top-first, so reverse)
                    $ancestors = @($ctrlStack.ToArray() | ForEach-Object { $_.Name })
                    [array]::Reverse($ancestors)
                    $ctrlStack.Push([pscustomobject]@{ Indent = $indent; Name = $key })
                    $curControl = $key
                    $typeShort = ($ctrlType -split '@')[0]
                    [void]$controls.Add([pscustomobject]@{
                        name = $key; type = $typeShort; screen = $screenLabel; file = $relPath; line = ($i + 1)
                        depth = $depth; ancestors = $ancestors
                    })
                }
                continue
            }

            # Property with an inline formula ("Prop: =...") OR a block scalar
            # ("Prop: |", "Prop: |-", "Prop: >", or "Prop:" then indented lines).
            if ($trim -match '^([A-Za-z_][\w]*):\s*(.*)$') {
                $propName = $Matches[1]
                $remainder = $Matches[2].Trim()
                if ($propName -in @('Control','Children','Properties','Components','Groups','Variant')) { continue }

                $startLine = $i + 1
                $text = $null
                $isInline = ($remainder -like '=*')
                $isBlock  = ($remainder -eq '' -or $remainder -match '^[|>][-+]?\d*$')
                if (-not $isInline -and -not $isBlock) { continue }   # plain non-formula scalar
                if ($isInline) {
                    $text = $remainder
                }
                else {
                    # block scalar: gather subsequent lines more-indented than the prop
                    $sb = New-Object System.Text.StringBuilder
                    for ($k = $i + 1; $k -lt $n; $k++) {
                        if ($lines[$k] -match '^\s*$') { [void]$sb.AppendLine(''); continue }
                        if ((Get-Indent $lines[$k]) -le $indent) { break }
                        [void]$sb.AppendLine($lines[$k].Trim())
                    }
                    $text = $sb.ToString().Trim()
                }
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    # Determine owning control: nearest control ancestor from the control-only
                    # stack; fall back to the screen label when outside any control scope.
                    $owner = if ($ctrlStack.Count -gt 0) { $ctrlStack.Peek().Name } else { $screenLabel }
                    [void]$formulas.Add([pscustomobject]@{
                        screen = $screenLabel; control = $owner; property = $propName
                        file = $relPath; line = $startLine; text = $text
                    })
                }
            }
        }
    }

    # Sort controls deterministically so position-based IDs (added later) are stable.
    $controls = @($controls | Sort-Object name, file, line)

    # ============================================================================
    # CUSTOM PROPERTIES: collect (componentName, propName) pairs from component files.
    # CustomProperties: block in a .pa.yaml component file lists each prop as a child key.
    # Structure:
    #   CustomProperties:            <- marker line at indent N
    #       FooterText:              <- direct child at indent N+step (= property name)
    #           PropertyKind: Input  <- metadata at indent N+step+step (skipped)
    #       UnusedProp:              <- another direct child (= property name)
    # ============================================================================
    $compCustomProps = New-Object System.Collections.ArrayList  # {compName, propName, file, line}
    foreach ($f in ($paFiles | Where-Object {
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '\.pa$',''
        $compFiles.ContainsKey($stem)
    })) {
        $compName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) -replace '\.pa$',''
        $relPath  = (Join-Path 'src' ($f.FullName.Substring($srcDir.FullName.Length).TrimStart('\','/'))) -replace '\\','/'
        $lines    = Get-Content -LiteralPath $f.FullName
        $nLines   = $lines.Count
        $inCP     = $false   # currently inside a CustomProperties: block
        $cpIndent = -1       # indent of the CustomProperties: marker
        $propIndent = -1     # indent of direct prop-name children (set on first child seen)

        for ($i = 0; $i -lt $nLines; $i++) {
            $line = $lines[$i]
            if ($line -match '^\s*$') { continue }
            $indent = Get-Indent $line
            $trim   = $line.Trim()

            if ($inCP) {
                # Exit the block when we return to or above the CustomProperties: indent
                if ($indent -le $cpIndent) {
                    $inCP = $false; $cpIndent = -1; $propIndent = -1
                    # Fall through: this line may start another CustomProperties: block
                } else {
                    # First non-empty line inside the block sets the prop-name indent level
                    if ($propIndent -lt 0) { $propIndent = $indent }

                    # Lines at prop-name indent are property declarations; deeper = their metadata
                    if ($indent -eq $propIndent -and $trim -match '^([A-Za-z_][\w]*):\s*$') {
                        [void]$compCustomProps.Add([pscustomobject]@{
                            compName = $compName; propName = $Matches[1]; file = $relPath; line = ($i + 1)
                        })
                    }
                    continue
                }
            }

            # Detect CustomProperties: marker (not inside one already)
            if ($trim -imatch '^CustomProperties\s*:\s*$') {
                $inCP     = $true
                $cpIndent = $indent
                $propIndent = -1
            }
        }
    }

    # All formula text concatenated for reference counting / token scans
    $allText = ($formulas | ForEach-Object { $_.text }) -join "`n"

    # ============================================================================
    # DATA SOURCES + CONNECTIONS  (\DataSources\*.json, \Connections\*.json)
    # ============================================================================
    $dataSources = New-Object System.Collections.ArrayList
    $dsDir = Get-ChildItem -Path $appExtract -Recurse -Directory | Where-Object { $_.Name -ieq 'DataSources' } | Select-Object -First 1
    if ($dsDir) {
        foreach ($dsf in Get-ChildItem -Path $dsDir.FullName -Recurse -File -Filter '*.json') {
            $dsName = [System.IO.Path]::GetFileNameWithoutExtension($dsf.Name)
            $typeRaw = ''
            try {
                $dj = Get-Content -LiteralPath $dsf.FullName -Raw | ConvertFrom-Json
                foreach ($p in 'Type','ApiId','ServiceKind','DatasetName','TableName') {
                    if ($dj.PSObject.Properties.Name -contains $p -and $dj.$p) { $typeRaw += ' ' + [string]$dj.$p }
                }
                $raw = (Get-Content -LiteralPath $dsf.FullName -Raw)
                $typeRaw += ' ' + $raw
            } catch { }
            [void]$dataSources.Add([pscustomobject]@{
                name = $dsName
                connector = (Resolve-Connector $typeRaw)
            })
        }
    }
    # De-dup data sources by name
    $dataSources = @($dataSources | Sort-Object name -Unique)

    # ============================================================================
    # VARIABLES, COLLECTIONS, NAVIGATION  (from formula text)
    # ============================================================================
    $globals = @{}   ; $contexts = @{} ; $collections = @{}
    foreach ($fm in $formulas) {
        foreach ($m in [regex]::Matches($fm.text, '(?i)\bSet\s*\(\s*([A-Za-z_][\w]*)')) { $globals[$m.Groups[1].Value] = $fm.file }
        foreach ($m in [regex]::Matches($fm.text, '(?i)\bUpdateContext\s*\(\s*\{\s*([A-Za-z_][\w]*)')) { $contexts[$m.Groups[1].Value] = $fm.file }
        foreach ($m in [regex]::Matches($fm.text, '(?i)\b(?:Clear)?Collect\s*\(\s*([A-Za-z_][\w]*)')) { $collections[$m.Groups[1].Value] = $fm.file }
    }

    function Count-Refs {
        param([string] $Name)
        ([regex]::Matches($allText, '(?<![\w.])' + [regex]::Escape($Name) + '\b')).Count
    }

    $variables = New-Object System.Collections.ArrayList
    foreach ($g in $globals.Keys) {
        $assign = ([regex]::Matches($allText, '(?i)\bSet\s*\(\s*' + [regex]::Escape($g) + '\b')).Count
        $total  = Count-Refs $g
        [void]$variables.Add([pscustomobject]@{ name=$g; scope='global'; definedIn=$globals[$g]; referenced=($total - $assign) })
    }
    foreach ($c in $contexts.Keys) {
        $assign = ([regex]::Matches($allText, '(?i)\bUpdateContext\s*\(\s*\{\s*' + [regex]::Escape($c) + '\b')).Count
        $total  = Count-Refs $c
        [void]$variables.Add([pscustomobject]@{ name=$c; scope='context'; definedIn=$contexts[$c]; referenced=($total - $assign) })
    }
    $collectionList = New-Object System.Collections.ArrayList
    foreach ($cl in $collections.Keys) {
        $assign = ([regex]::Matches($allText, '(?i)\b(?:Clear)?Collect\s*\(\s*' + [regex]::Escape($cl) + '\b')).Count
        $total  = Count-Refs $cl
        [void]$collectionList.Add([pscustomobject]@{ name=$cl; definedIn=$collections[$cl]; referenced=($total - $assign) })
    }

    # Sort variables and collections deterministically for stable position-based IDs.
    $variables      = @($variables      | Sort-Object name, scope, definedIn)
    $collectionList = @($collectionList | Sort-Object name, definedIn)

    # Navigation edges (from Navigate / Back)
    $navigation = New-Object System.Collections.ArrayList
    foreach ($fm in $formulas) {
        foreach ($m in [regex]::Matches($fm.text, '(?i)\bNavigate\s*\(\s*([A-Za-z_][\w]*)')) {
            [void]$navigation.Add([pscustomobject]@{ from=$fm.screen; to=$m.Groups[1].Value; via='Navigate' })
        }
        if ($fm.text -imatch '\bBack\s*\(') {
            [void]$navigation.Add([pscustomobject]@{ from=$fm.screen; to='(previous)'; via='Back' })
        }
    }

    # Start screen (App.StartScreen if declared)
    $startScreen = $null
    $ssRec = $formulas | Where-Object { $_.screen -eq 'App' -and $_.property -ieq 'StartScreen' } | Select-Object -First 1
    if ($ssRec) { $startScreen = ($ssRec.text -replace '^=','').Trim() }

    # Screen list (files that are neither App nor Component)
    $screenNames = @($paFiles |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '\.pa$','' } |
        Where-Object { $_ -ne 'App' -and -not $compFiles.ContainsKey($_) } | Sort-Object -Unique)

    # Per-screen weight + trigger flags (drives the model's targeted reads)
    $screenInfo = New-Object System.Collections.ArrayList
    foreach ($sn in $screenNames) {
        $sf = $formulas | Where-Object { $_.screen -eq $sn }
        $sText = ($sf | ForEach-Object { $_.text }) -join "`n"
        $ctrlCount = @($controls | Where-Object { $_.screen -eq $sn }).Count
        $relFile = ($paFiles | Where-Object { ([System.IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '\.pa$','') -eq $sn } | Select-Object -First 1)
        $relFilePath = if ($relFile) { ('src/' + $relFile.FullName.Substring($srcDir.FullName.Length).TrimStart('\','/')) -replace '\\','/' } else { $null }
        [void]$screenInfo.Add([pscustomobject]@{
            name = $sn
            file = $relFilePath
            controlCount = $ctrlCount
            formulaBytes = [System.Text.Encoding]::UTF8.GetByteCount($sText)
            triggers = [pscustomobject]@{
                delegation     = [bool]($sText -imatch '\b(Filter|LookUp|Search|Sort|SortByColumns|Sum|Average|Min|Max|CountRows|CountIf)\s*\(')
                nPlusOne       = [bool]($sText -imatch '(?i)\bForAll\s*\(' -or $sText -imatch '(?i)Gallery')
                errorHandling  = [bool]($sText -imatch '(?i)\b(Patch|Collect|Remove|RemoveIf|UpdateIf|SubmitForm)\s*\(')
                deepNesting    = [bool]($sf | Where-Object { $_.text.Length -gt 500 })
            }
        })
    }

    # ============================================================================
    # DETERMINISTIC FINDINGS
    # ============================================================================
    $det = New-Object System.Collections.ArrayList

    # --- Default control names (Confirmed) ---
    foreach ($c in $controls) {
        if ($c.name -match $defaultNameRegex) {
            [void]$det.Add((New-Finding -Prefix 'DN' -Type 'default-control-name' `
                -Category 'Maintainability & naming' -Severity 'Medium' -Confidence 'Confirmed' -Tier 'narrative' `
                -Location @{ screen=$c.screen; control=$c.name; property=$null; file=$c.file; line=$c.line } `
                -Evidence "$($c.name) ($($c.type))" `
                -Message "Control '$($c.name)' uses a default auto-generated name. Rename with a 3-char type prefix + purpose, e.g. '$( ($c.type.Substring(0,[Math]::Min(3,$c.type.Length))).ToLower() )Purpose'." `
                -SortKey "$($c.file)|$($c.line)|$($c.name)"))
        }
    }
    # --- Default screen names (Confirmed) ---
    foreach ($sn in $screenNames) {
        if ($sn -match '^(Screen)?_?\d+$' -or $sn -match '^Screen\d+$') {
            $rf = ($screenInfo | Where-Object { $_.name -eq $sn } | Select-Object -First 1)
            [void]$det.Add((New-Finding -Prefix 'DS' -Type 'default-screen-name' `
                -Category 'Maintainability & naming' -Severity 'Medium' -Confidence 'Confirmed' -Tier 'narrative' `
                -Location @{ screen=$sn; control=$null; property=$null; file=($rf.file); line=1 } `
                -Evidence $sn `
                -Message "Screen '$sn' uses a default name. Rename to plain language ending in 'Screen' (e.g. 'OrderDetailsScreen')." `
                -SortKey "$($rf.file)|1|$sn"))
        }
    }
    # --- Variable / collection prefix violations (Confirmed, Low) ---
    foreach ($v in $variables) {
        $ok = if ($v.scope -eq 'global') { $v.name -clike 'gbl*' } else { $v.name -clike 'loc*' }
        if (-not $ok) {
            $want = if ($v.scope -eq 'global') { 'gbl' } else { 'loc' }
            [void]$det.Add((New-Finding -Prefix 'VP' -Type 'variable-prefix' `
                -Category 'Maintainability & naming' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
                -Location @{ screen=$null; control=$null; property=$null; file=$v.definedIn; line=$null } `
                -Evidence "$($v.scope) variable '$($v.name)'" `
                -Message "$($v.scope) variable '$($v.name)' lacks the '$want' prefix convention." `
                -SortKey "$($v.name)|$($v.definedIn)|"))
        }
    }
    foreach ($cl in $collectionList) {
        if (-not ($cl.name -clike 'col*')) {
            [void]$det.Add((New-Finding -Prefix 'VP' -Type 'collection-prefix' `
                -Category 'Maintainability & naming' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
                -Location @{ screen=$null; control=$null; property=$null; file=$cl.definedIn; line=$null } `
                -Evidence "collection '$($cl.name)'" `
                -Message "Collection '$($cl.name)' lacks the 'col' prefix convention." `
                -SortKey "$($cl.name)|$($cl.definedIn)|"))
        }
    }

    # --- Dead / unused (Confirmed for data; Potential for controls = layout judgment) ---
    foreach ($v in $variables) {
        if ($v.referenced -le 0) {
            [void]$det.Add((New-Finding -Prefix 'UV' -Type 'unused-variable' `
                -Category 'Dead / unused' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
                -Location @{ screen=$null; control=$null; property=$null; file=$v.definedIn; line=$null } `
                -Evidence "$($v.scope) variable '$($v.name)'" `
                -Message "$($v.scope) variable '$($v.name)' is set but never read. Remove it or wire it up." `
                -SortKey "$($v.name)|$($v.definedIn)|"))
        }
    }
    foreach ($cl in $collectionList) {
        if ($cl.referenced -le 0) {
            [void]$det.Add((New-Finding -Prefix 'UC' -Type 'unused-collection' `
                -Category 'Dead / unused' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
                -Location @{ screen=$null; control=$null; property=$null; file=$cl.definedIn; line=$null } `
                -Evidence "collection '$($cl.name)'" `
                -Message "Collection '$($cl.name)' is built but never referenced. Remove the Collect/ClearCollect or use it." `
                -SortKey "$($cl.name)|$($cl.definedIn)|"))
        }
    }
    foreach ($ds in $dataSources) {
        if ((Count-Refs $ds.name) -le 0) {
            [void]$det.Add((New-Finding -Prefix 'UD' -Type 'unused-datasource' `
                -Category 'Dead / unused' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
                -Location @{ screen=$null; control=$null; property=$null; file='\DataSources'; line=$null } `
                -Evidence "data source '$($ds.name)' ($($ds.connector))" `
                -Message "Data source '$($ds.name)' is connected but never referenced in any formula. Remove the connection to shrink the app." `
                -SortKey "$($ds.name)|\DataSources|"))
        }
    }
    # Orphan screens: never a Navigate target and not the start screen
    $navTargets = @($navigation | Where-Object { $_.via -eq 'Navigate' } | ForEach-Object { $_.to } | Sort-Object -Unique)
    foreach ($sn in $screenNames) {
        $isTarget = $navTargets -contains $sn
        $isStart  = ($startScreen -and ($startScreen -imatch ('\b' + [regex]::Escape($sn) + '\b')))
        if (-not $isTarget -and -not $isStart) {
            $rf = ($screenInfo | Where-Object { $_.name -eq $sn } | Select-Object -First 1)
            [void]$det.Add((New-Finding -Prefix 'OS' -Type 'orphan-screen' `
                -Category 'Dead / unused' -Severity 'Medium' -Confidence 'Potential' -Tier 'narrative' `
                -Location @{ screen=$sn; control=$null; property=$null; file=($rf.file); line=1 } `
                -Evidence "screen '$sn'" `
                -Message "Screen '$sn' is never targeted by a Navigate() and is not the start screen. It may be an orphan (verify it isn't the default first screen or reached via a variable)." `
                -SortKey "$sn|$($rf.file)|1"))
        }
    }
    # Unreferenced controls (Potential - pure-layout controls are legitimately unreferenced)
    foreach ($c in $controls) {
        if ($c.type -imatch 'Screen') { continue }
        $refs = ([regex]::Matches($allText, '(?<![\w.])' + [regex]::Escape($c.name) + '(?:\.|\b)')).Count
        if ($refs -le 0) {
            [void]$det.Add((New-Finding -Prefix 'UR' -Type 'unreferenced-control' `
                -Category 'Dead / unused' -Severity 'Low' -Confidence 'Potential' -Tier 'enumeration' `
                -Location @{ screen=$c.screen; control=$c.name; property=$null; file=$c.file; line=$c.line } `
                -Evidence "$($c.name) ($($c.type))" `
                -Message "Control '$($c.name)' is never referenced by any formula. If it is purely decorative/layout this is fine; otherwise it may be dead. (Verify.)" `
                -SortKey "$($c.file)|$($c.line)|$($c.name)"))
        }
    }

    # --- Unused custom components (UK) - Medium, narrative ---
    # A component is DEFINED when its file stem appears in $compFiles.Keys.
    # A component is INSTANTIATED when any control's type equals the component name
    # (the parser records type = ($ctrlType -split '@')[0] from the Control: line).
    # A component's own internal child controls have ordinary types (Label, Button, etc.)
    # and their screen label equals the component name — they do NOT create a false
    # "instantiated" signal because their type is 'Label', 'Button', etc., not 'cmpXxx'.
    $ukCitation = 'coding-standards-and-performance.md section 5 (Components & reuse) - https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps | https://learn.microsoft.com/power-apps/maker/canvas-apps/create-component'
    $instantiatedComponentTypes = @($controls | ForEach-Object { $_.type } | Sort-Object -Unique)
    foreach ($compName in @($compFiles.Keys)) {
        if ([string]::IsNullOrWhiteSpace($compName)) { continue }
        if ($instantiatedComponentTypes -notcontains $compName) {
            # Determine the component's source file path
            $compSrcFile = $paFiles | Where-Object {
                ([System.IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '\.pa$','') -ieq $compName
            } | Select-Object -First 1
            $compRelPath = if ($compSrcFile) {
                ('src/' + $compSrcFile.FullName.Substring($srcDir.FullName.Length).TrimStart('\','/')) -replace '\\','/'
            } else { 'src/Components' }
            [void]$det.Add((New-Finding -Prefix 'UK' -Type 'unused-component' `
                -Category 'Dead / unused' -Severity 'Medium' -Confidence 'Confirmed' -Tier 'narrative' `
                -Citation $ukCitation `
                -Location @{ screen=$compName; control=$null; property=$null; file=$compRelPath; line=1 } `
                -Evidence "component '$compName'" `
                -Message "Component '$compName' is defined but never instantiated on any screen. Either use it or delete the component file to reduce app size." `
                -SortKey "$compRelPath|1|$compName"))
        }
    }

    # --- Unused component custom property (UP) - Low, enumeration ---
    # A custom property defined on a component but never READ in any formula text.
    # "Used" = either the qualified token "componentName.PropName" OR the bare token "PropName"
    # appears anywhere in $allText (word-boundary regex, same as Count-Refs).
    # Instance-assignment lines (e.g. "FooterText: ="hi"" in the consumer screen) have the
    # property name as a YAML key, NOT inside formula text, so they do NOT count as a reference.
    # Citation: coding-standards-and-performance.md section 5 (Components & reuse)
    $upCitation = 'coding-standards-and-performance.md section 5 (Components & reuse) - https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps | https://learn.microsoft.com/power-apps/maker/canvas-apps/create-component'
    foreach ($cp in $compCustomProps) {
        # A property is "read" if it appears qualified ("cmpFooter.MyProp", from an instance)
        # or bare ("MyProp", how a component references its own property internally).
        # KNOWN LIMITATION (regex parser): the bare-token check can FALSE-NEGATIVE (suppress a
        # real UP finding) for generic property names that collide with common tokens elsewhere
        # in formula text (e.g. a property literally named "Text"/"Color"/"Width"). The qualified
        # reference is the strong signal; the bare check is a conservative under-report. Acceptable
        # for an enumeration-tier/Low finding (we prefer missing one over a false positive).
        $qualifiedRef = ([regex]::Matches($allText, '(?<![\w.])' + [regex]::Escape($cp.compName) + '\.' + [regex]::Escape($cp.propName) + '\b')).Count -gt 0
        $bareRef = Count-Refs $cp.propName
        if (-not $qualifiedRef -and $bareRef -le 0) {
            [void]$det.Add((New-Finding -Prefix 'UP' -Type 'unused-component-property' `
                -Category 'Dead / unused' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
                -Citation $upCitation `
                -Location @{ screen=$cp.compName; control=$null; property=$cp.propName; file=$cp.file; line=$cp.line } `
                -Evidence "component '$($cp.compName)' property '$($cp.propName)'" `
                -Message "Custom property '$($cp.propName)' on component '$($cp.compName)' is defined but never referenced in any formula. Remove it or wire it up." `
                -SortKey "$($cp.file)|$($cp.line)|$($cp.compName).$($cp.propName)"))
        }
    }

    # --- Commented-out code (CC) - Low, enumeration ---
    # Scans each formula's CODE spans (string literals blanked out so //inside-a-URL is ignored).
    # Flags // and /* */ comments whose content looks like code, NOT prose.
    # Code heuristic: contains a function-call pattern ([A-Za-z_]\w*\s*\() OR one of ; { }
    # Prose comments (e.g. "// Submit the order to the back end") are intentional and NOT flagged.
    # Citation: coding-standards-and-performance.md section 1 Comments
    $ccCitation = 'coding-standards-and-performance.md section 1 (Comments) - https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability'
    foreach ($fm in $formulas) {
        $spans = Split-FormulaSpans $fm.text
        $codeText = $spans.Code
        $codeLikeLines = New-Object System.Collections.ArrayList

        # 1. Single-line // comments
        foreach ($m in [regex]::Matches($codeText, '//(.*)$', [System.Text.RegularExpressions.RegexOptions]::Multiline)) {
            $c = $m.Groups[1].Value.Trim()
            if ($c -match '[A-Za-z_]\w*\s*\(' -or $c -match '[;{}=]') {
                [void]$codeLikeLines.Add($m.Value.Trim())
            }
        }

        # 2. Block /* ... */ comments (single-line and multi-line)
        foreach ($m in [regex]::Matches($codeText, '/\*([\s\S]*?)\*/', [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
            $c = $m.Groups[1].Value.Trim()
            if ($c -match '[A-Za-z_]\w*\s*\(' -or $c -match '[;{}=]') {
                [void]$codeLikeLines.Add($m.Value.Trim())
            }
        }

        if ($codeLikeLines.Count -gt 0) {
            $evid = ($codeLikeLines | Select-Object -First 3) -join ' | '
            if ($evid.Length -gt 200) { $evid = $evid.Substring(0, 200) + ' ...' }
            $ccCount = $codeLikeLines.Count
            $ccMsg = "Commented-out code found in $($fm.control).$($fm.property). Source control preserves history - remove dead code rather than commenting it out. ($ccCount code-like comment(s) found.)"
            [void]$det.Add((New-Finding -Prefix 'CC' -Type 'commented-out-code' `
                -Category 'Maintainability & naming' -Severity 'Low' -Confidence 'Potential' -Tier 'enumeration' `
                -Citation $ccCitation `
                -Location @{ screen=$fm.screen; control=$fm.control; property=$fm.property; file=$fm.file; line=$fm.line } `
                -Evidence $evid `
                -Message $ccMsg `
                -SortKey "$($fm.file)|$($fm.line)|$($fm.control)"))
        }
    }

    # --- Stub event handlers (EH) - Low, enumeration, Confirmed ---
    # An event property (name matches ^On[A-Z]) whose formula text normalises to "false"
    # is a stub — the maker left the Power Apps Studio default without wiring real logic.
    # Citation: coding-standards-and-performance.md section 1 (Stub/empty event handlers)
    # - general maintainability guidance: https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability
    $ehCitation = 'coding-standards-and-performance.md section 1 (Stub/empty event handlers) - general maintainability guidance: https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability'
    foreach ($fm in $formulas) {
        if ($fm.property -notmatch '^On[A-Z]') { continue }
        $normalized = ($fm.text -replace '^=','').Trim()
        if ($normalized -ine 'false') { continue }
        [void]$det.Add((New-Finding -Prefix 'EH' -Type 'stub-event-handler' `
            -Category 'Maintainability & naming' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
            -Citation $ehCitation `
            -Location @{ screen=$fm.screen; control=$fm.control; property=$fm.property; file=$fm.file; line=$fm.line } `
            -Evidence "$($fm.control).$($fm.property) = false" `
            -Message "Event handler '$($fm.control).$($fm.property)' is a stub (formula is literally 'false'). Either wire up real logic or remove the property." `
            -SortKey "$($fm.file)|$($fm.line)|$($fm.control).$($fm.property)"))
    }

    # --- Permanently hidden controls (HC) - Low, enumeration, Confirmed ---
    # A control whose Visible property formula normalises to the literal "false" is
    # permanently hidden: it is never rendered and cannot be reached by the user.
    # If intentional the reason should be documented in a comment; if unintentional the
    # control is dead weight that increases package size and can mislead maintainers.
    # Citation: coding-standards-and-performance.md section 2 (Permanently hidden controls)
    # - performance-tips reference: https://learn.microsoft.com/power-apps/maker/canvas-apps/performance-tips
    $hcCitation = 'coding-standards-and-performance.md section 2 (Permanently hidden controls) - general maintainability guidance: https://learn.microsoft.com/power-apps/maker/canvas-apps/performance-tips'
    foreach ($fm in $formulas) {
        if ($fm.property -ine 'Visible') { continue }
        $normalized = ($fm.text -replace '^=','').Trim()
        if ($normalized -ine 'false') { continue }
        [void]$det.Add((New-Finding -Prefix 'HC' -Type 'permanently-hidden-control' `
            -Category 'Dead / unused' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
            -Citation $hcCitation `
            -Location @{ screen=$fm.screen; control=$fm.control; property=$fm.property; file=$fm.file; line=$fm.line } `
            -Evidence "$($fm.control).Visible = false" `
            -Message "Control '$($fm.control)' has Visible permanently set to 'false'. If intentional, document the reason in a comment; otherwise remove the control or wire up a dynamic visibility expression." `
            -SortKey "$($fm.file)|$($fm.line)|$($fm.control)"))
    }

    # --- Dead conditional branches (DB) - Low, enumeration, Confirmed ---
    # A formula whose CODE span contains If(true, ...) or If(false, ...) has a permanently
    # dead branch - the literal boolean makes one branch unreachable.
    # Uses Split-FormulaSpans so "If(false,...)" inside a string literal is never matched.
    # Word-boundary after the literal prevents matching If(falseFlag,...).
    # Citation: coding-standards-and-performance.md section 2 (Dead conditional branches)
    # - code optimization: https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-optimization
    $dbCitation = 'coding-standards-and-performance.md section 2 (Dead conditional branches) - general: https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-optimization'
    $dbPattern  = [regex]::new('\bIf\s*\(\s*(false|true)\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($fm in $formulas) {
        $spans      = Split-FormulaSpans $fm.text
        $codeText   = $spans.Code
        $dbHits     = @($dbPattern.Matches($codeText))
        if ($dbHits.Count -gt 0) {
            $countMsg = if ($dbHits.Count -eq 1) { '1 dead branch' } else { "$($dbHits.Count) dead branches" }
            $evid     = "$($fm.control).$($fm.property): $($dbHits.Count) dead-branch If() call(s)"
            $dbMsg    = "Dead conditional branch in $($fm.control).$($fm.property) - If() has a literal boolean as its condition ($countMsg). The dead branch is never evaluated; remove it or replace with the live result directly."
            [void]$det.Add((New-Finding -Prefix 'DB' -Type 'dead-conditional-branch' `
                -Category 'Dead / unused' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
                -Citation $dbCitation `
                -Location @{ screen=$fm.screen; control=$fm.control; property=$fm.property; file=$fm.file; line=$fm.line } `
                -Evidence $evid `
                -Message $dbMsg `
                -SortKey "$($fm.file)|$($fm.line)|$($fm.control).$($fm.property)"))
        }
    }

    # --- Exact duplicate formulas (Confirmed, Redundancy) ---
    $byNorm = @{}
    foreach ($fm in $formulas) {
        $norm = ($fm.text -replace '\s+',' ').Trim()
        if ($norm.Length -lt 40) { continue }              # ignore trivial formulas
        if ($norm -imatch '^=?(true|false|parent\.|self\.|rgba|color\.)') { continue }
        if (-not $byNorm.ContainsKey($norm)) { $byNorm[$norm] = New-Object System.Collections.ArrayList }
        [void]$byNorm[$norm].Add($fm)
    }
    foreach ($k in $byNorm.Keys) {
        $grp = $byNorm[$k]
        if ($grp.Count -ge 2) {
            $locs = @($grp | ForEach-Object { "$($_.screen)->$($_.control).$($_.property) ($($_.file):$($_.line))" })
            $first = $grp[0]
            $snip = if ($first.text.Length -gt 240) { $first.text.Substring(0,240) + ' ...' } else { $first.text }
            [void]$det.Add((New-Finding -Prefix 'XD' -Type 'exact-duplicate-formula' `
                -Category 'Redundancy & reuse' -Severity 'Medium' -Confidence 'Confirmed' -Tier 'narrative' `
                -Location @{ screen=$first.screen; control=$first.control; property=$first.property; file=$first.file; line=$first.line } `
                -Evidence $snip `
                -Message ("Identical formula repeated $($grp.Count) times: " + ($locs -join '; ') + ". Extract to a named formula (App.Formulas), a component, or a With() subexpression.") `
                -SortKey "$($first.file)|$($first.line)|$k"))
        }
    }

    # ============================================================================
    # JUDGMENT LEADS (the model confirms/rejects using the bundled references)
    # ============================================================================
    $leads = New-Object System.Collections.ArrayList
    $serverSourceNames = @($dataSources | Where-Object { $_.connector -in @('SharePoint','SQL Server','Dataverse','Excel') } | ForEach-Object { $_.name })

    foreach ($fm in $formulas) {
        $t = $fm.text
        $snip = if ($t.Length -gt 200) { $t.Substring(0,200) + ' ...' } else { $t }

        # Delegation candidates: a delegable-or-not function whose 1st arg is a server source
        foreach ($m in [regex]::Matches($t, '(?i)\b(Filter|LookUp|Search|Sort|SortByColumns|Sum|Average|Min|Max|CountRows|CountIf|FirstN|LastN|Last|Choices|Concat|GroupBy|Ungroup)\s*\(\s*([A-Za-z_][\w]*)')) {
            $fn = $m.Groups[1].Value; $arg = $m.Groups[2].Value
            $isServer = $serverSourceNames -contains $arg
            $isCollection = $collections.ContainsKey($arg)
            if ($isCollection) { continue }   # collections need no delegation - avoid false positives
            $srcHint = if ($isServer) { "First arg '$arg' resolves to a server data source." } else { "First arg '$arg' - resolve its type from \DataSources before flagging (skip if it is a collection/variable/static Excel)." }
            $always = ($alwaysLocalFns -contains $fn)
            $kind = if ($always) { 'non-delegable-always-local' } else { 'delegation-candidate' }
            $alwaysHint = if ($always) { " '$fn' is non-delegable on every connector." } else { '' }
            $delHint = "$fn on '$arg'. $srcHint Check delegation.md for the connector matrix. ALWAYS tag delegation findings 'Potential - verify row count'." + $alwaysHint
            [void]$leads.Add((New-Lead -Kind $kind -Category 'Delegation & data efficiency' `
                -Screen $fm.screen -Control $fm.control -Property $fm.property -File $fm.file -Line $fm.line `
                -Snippet $snip -Hint $delHint))
        }

        # Performance: heavy App.OnStart
        if ($fm.screen -eq 'App' -and $fm.property -ieq 'OnStart') {
            $setN = ([regex]::Matches($t,'(?i)\bSet\s*\(')).Count
            $colN = ([regex]::Matches($t,'(?i)\b(?:Clear)?Collect\s*\(')).Count
            [void]$leads.Add((New-Lead -Kind 'heavy-onstart' -Category 'Performance' `
                -Screen 'App' -Control 'App' -Property 'OnStart' -File $fm.file -Line $fm.line `
                -Snippet $snip `
                -Hint "App.OnStart contains $setN Set() and $colN Collect() calls. Static initializations belong in App.Formulas (named formulas, ~80% load win). Keep Set only for state that changes. See coding-standards-and-performance.md."))
            if ($t -imatch '(?i)\bNavigate\s*\(') {
                [void]$leads.Add((New-Lead -Kind 'navigate-in-onstart' -Category 'Performance' `
                    -Screen 'App' -Control 'App' -Property 'OnStart' -File $fm.file -Line $fm.line `
                    -Snippet $snip `
                    -Hint "Navigate() inside App.OnStart blocks first render until OnStart finishes. Replace with declarative App.StartScreen. (Confirmed pattern.)"))
            }
        }

        # Performance: sequential independent data calls -> Concurrent opportunity
        if ($fm.property -imatch '(OnStart|OnVisible|OnSelect)') {
            $ccN = ([regex]::Matches($t,'(?i)\b(?:Clear)?Collect\s*\(')).Count
            if ($ccN -ge 2 -and $t -notmatch '(?i)\bConcurrent\s*\(') {
                [void]$leads.Add((New-Lead -Kind 'concurrent-opportunity' -Category 'Performance' `
                    -Screen $fm.screen -Control $fm.control -Property $fm.property -File $fm.file -Line $fm.line `
                    -Snippet $snip `
                    -Hint "$ccN sequential Collect/ClearCollect calls. If independent, wrap in Concurrent() to wait only for the longest. Caveat: only when calls don't depend on each other."))
            }
        }

        # Performance: N+1 - data call inside ForAll
        foreach ($m in [regex]::Matches($t, '(?i)\bForAll\s*\(')) {
            if ($t -imatch '(?i)\b(LookUp|Filter|Search)\s*\(') {
                [void]$leads.Add((New-Lead -Kind 'n-plus-1' -Category 'Performance' `
                    -Screen $fm.screen -Control $fm.control -Property $fm.property -File $fm.file -Line $fm.line `
                    -Snippet $snip `
                    -Hint "A LookUp/Filter/Search appears inside ForAll - potential per-row (N+1) network calls. Batch with a single Collect up front, or reshape at the source. (Potential - high impact.)"))
            }
        }

        # Error handling: mutation without IfError / Errors() in the same formula
        if ($t -imatch '(?i)\b(Patch|Collect|Remove|RemoveIf|UpdateIf|SubmitForm)\s*\(' -and $t -notmatch '(?i)\b(IfError|Errors)\s*\(') {
            [void]$leads.Add((New-Lead -Kind 'unhandled-mutation' -Category 'Error handling & resilience' `
                -Screen $fm.screen -Control $fm.control -Property $fm.property -File $fm.file -Line $fm.line `
                -Snippet $snip `
                -Hint "A data mutation (Patch/Collect/Remove/SubmitForm) with no IfError() wrapper or Errors() check nearby. Recommend user-facing error handling. (Potential - some operations are low-risk; judge.)"))
        }
    }

    # Stamp stable IDs on all findings and leads before emitting.
    Stamp-Ids -Findings $det -Leads $leads

    # ============================================================================
    # EMIT: enumeration.md (one table per finding type - 100% complete by construction)
    # ============================================================================
    $enumMd = New-Object System.Text.StringBuilder
    [void]$enumMd.AppendLine("# Deterministic Findings - $displayName")
    [void]$enumMd.AppendLine("")
    [void]$enumMd.AppendLine("_Generated by analyze-canvas.ps1. Every deterministic finding appears as a row._")
    [void]$enumMd.AppendLine("")

    # Group by category then type so sections are stable
    $categories = @($det | ForEach-Object { $_.category } | Sort-Object -Unique)
    foreach ($cat in $categories) {
        [void]$enumMd.AppendLine("## $cat")
        [void]$enumMd.AppendLine("")
        $catFindings = @($det | Where-Object { $_.category -eq $cat })
        $types = @($catFindings | ForEach-Object { $_.type } | Sort-Object -Unique)
        foreach ($typ in $types) {
            $typeFindings = @($catFindings | Where-Object { $_.type -eq $typ })
            # Citation: use the first finding's citation field, or a placeholder
            $citationVal = $null
            foreach ($tf in $typeFindings) { if ($tf.citation) { $citationVal = $tf.citation; break } }
            $citationLine = if ($citationVal) { "Citation: $citationVal" } else { "Citation: (see reference docs)" }
            [void]$enumMd.AppendLine("### $typ")
            [void]$enumMd.AppendLine("")
            [void]$enumMd.AppendLine("_$citationLine_")
            [void]$enumMd.AppendLine("")
            [void]$enumMd.AppendLine("| id | severity | location | evidence |")
            [void]$enumMd.AppendLine("| --- | --- | --- | --- |")
            foreach ($tf in $typeFindings) {
                $locScreen  = if ($tf.location.screen)   { $tf.location.screen }   else { '-' }
                $locControl = if ($tf.location.control)  { $tf.location.control }  else { '-' }
                $locFile    = if ($tf.location.file)     { $tf.location.file }     else { '-' }
                $locLine    = if ($null -ne $tf.location.line) { $tf.location.line } else { '-' }
                $locStr = "$locScreen/$locControl ($($locFile):$locLine)"
                # Encode pipes as the HTML entity so a formula snippet containing '|'
                # cannot break the markdown table on any renderer (GFM-safe).
                $evStr  = ($tf.evidence -replace '\|', '&#124;') -replace "`n",' '
                [void]$enumMd.AppendLine("| $($tf.id) | $($tf.severity) | $locStr | $evStr |")
            }
            [void]$enumMd.AppendLine("")
        }
    }
    $enumMd.ToString() | Out-File -FilePath (Join-Path $analysisOut 'enumeration.md') -Encoding utf8

    # ============================================================================
    # EMIT: summary.md (category x severity matrix + confirmed/potential + totals)
    # ============================================================================
    $summaryMd = New-Object System.Text.StringBuilder
    [void]$summaryMd.AppendLine("# Analysis Summary - $displayName")
    [void]$summaryMd.AppendLine("")

    # Build category x severity matrix
    $allCategories = @(
        'Maintainability & naming',
        'Dead / unused',
        'Redundancy & reuse',
        'Delegation & data efficiency',
        'Performance',
        'Error handling & resilience'
    )
    [void]$summaryMd.AppendLine("## Findings by category and severity")
    [void]$summaryMd.AppendLine("")
    [void]$summaryMd.AppendLine("| Category | High | Med | Low | Total |")
    [void]$summaryMd.AppendLine("| --- | --- | --- | --- | --- |")
    $sumHigh = 0; $sumMed = 0; $sumLow = 0
    foreach ($cat in $allCategories) {
        $catDet = @($det | Where-Object { $_.category -eq $cat })
        $high   = @($catDet | Where-Object { $_.severity -eq 'High' }).Count
        $med    = @($catDet | Where-Object { $_.severity -eq 'Medium' }).Count
        $low    = @($catDet | Where-Object { $_.severity -eq 'Low' }).Count
        $total  = $catDet.Count
        $sumHigh += $high; $sumMed += $med; $sumLow += $low
        [void]$summaryMd.AppendLine("| $cat | $high | $med | $low | $total |")
    }
    [void]$summaryMd.AppendLine("| **Total** | $sumHigh | $sumMed | $sumLow | $($det.Count) |")
    [void]$summaryMd.AppendLine("")

    # Confirmed/Potential split
    $confirmedCount = @($det | Where-Object { $_.confidence -eq 'Confirmed' }).Count
    $potentialCount = @($det | Where-Object { $_.confidence -eq 'Potential' }).Count
    [void]$summaryMd.AppendLine("## Confidence split")
    [void]$summaryMd.AppendLine("")
    [void]$summaryMd.AppendLine("| Confidence | Count |")
    [void]$summaryMd.AppendLine("| --- | --- |")
    [void]$summaryMd.AppendLine("| Confirmed | $confirmedCount |")
    [void]$summaryMd.AppendLine("| Potential | $potentialCount |")
    [void]$summaryMd.AppendLine("")

    # Totals
    [void]$summaryMd.AppendLine("**Total deterministic findings: $($det.Count)**")
    [void]$summaryMd.AppendLine("")
    [void]$summaryMd.AppendLine("**Judgment leads: $($leads.Count)**")
    [void]$summaryMd.AppendLine("")
    $summaryMd.ToString() | Out-File -FilePath (Join-Path $analysisOut 'summary.md') -Encoding utf8

    # ============================================================================
    # EMIT: index.json, mechanical-findings.json, index.md, status.json
    # ============================================================================
    $index = [ordered]@{
        app = [ordered]@{ name=$displayName; folder=$safeName; msapp=$chosen.Name; srcPath='src' }
        counts = [ordered]@{
            screens=$screenNames.Count; controls=$controls.Count; dataSources=$dataSources.Count
            variables=$variables.Count; collections=$collectionList.Count
        }
        startScreen = $startScreen
        screens = @($screenInfo)
        controls = @($controls | ForEach-Object { [ordered]@{ name=$_.name; type=$_.type; screen=$_.screen; depth=$_.depth; isDefaultName=([bool]($_.name -match $defaultNameRegex)) } })
        dataSources = @($dataSources | ForEach-Object { [ordered]@{ name=$_.name; connector=$_.connector } })
        collections = @($collectionList)
        variables = @($variables)
        navigation = @($navigation | Sort-Object from,to,via -Unique)
        components = @($compFiles.Keys)
    }
    ($index | ConvertTo-Json -Depth 12) | Out-File -FilePath (Join-Path $analysisOut 'index.json') -Encoding utf8

    $mech = [ordered]@{
        deterministicFindings = @($det)
        leads = @($leads)
    }
    ($mech | ConvertTo-Json -Depth 12) | Out-File -FilePath (Join-Path $analysisOut 'mechanical-findings.json') -Encoding utf8

    # --- index.md digest (human-browsable) ---
    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine("# Index - $displayName")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("Source app: ``$($chosen.Name)``  -  Persisted source: ``src/``")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("| Metric | Count |")
    [void]$md.AppendLine("| --- | --- |")
    [void]$md.AppendLine("| Screens | $($screenNames.Count) |")
    [void]$md.AppendLine("| Controls | $($controls.Count) |")
    [void]$md.AppendLine("| Data sources | $($dataSources.Count) |")
    [void]$md.AppendLine("| Variables | $($variables.Count) |")
    [void]$md.AppendLine("| Collections | $($collectionList.Count) |")
    [void]$md.AppendLine("| Deterministic findings | $($det.Count) |")
    [void]$md.AppendLine("| Judgment leads | $($leads.Count) |")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("## Screens (by weight - read the heaviest/flagged first)")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("| Screen | Controls | Formula bytes | Triggers |")
    [void]$md.AppendLine("| --- | --- | --- | --- |")
    foreach ($s in ($screenInfo | Sort-Object formulaBytes -Descending)) {
        $tr = @()
        if ($s.triggers.delegation) { $tr += 'delegation' }
        if ($s.triggers.nPlusOne) { $tr += 'n+1?' }
        if ($s.triggers.errorHandling) { $tr += 'mutations' }
        if ($s.triggers.deepNesting) { $tr += 'long-formulas' }
        [void]$md.AppendLine("| $($s.name) | $($s.controlCount) | $($s.formulaBytes) | $($tr -join ', ') |")
    }
    [void]$md.AppendLine("")
    [void]$md.AppendLine("## Data sources")
    [void]$md.AppendLine("")
    if ($dataSources.Count -eq 0) { [void]$md.AppendLine("_None declared._") }
    else { foreach ($d in $dataSources) { [void]$md.AppendLine("- **$($d.name)** - $($d.connector)") } }
    [void]$md.AppendLine("")
    [void]$md.AppendLine("## Navigation map")
    [void]$md.AppendLine("")
    $navUnique = @($navigation | Where-Object { $_.via -eq 'Navigate' } | Sort-Object from,to -Unique)
    if ($navUnique.Count -eq 0) { [void]$md.AppendLine("_No Navigate() calls found._") }
    else { foreach ($e in $navUnique) { [void]$md.AppendLine("- $($e.from) -> $($e.to)") } }
    if ($startScreen) { [void]$md.AppendLine(""); [void]$md.AppendLine("Start screen: ``$startScreen``") }
    $md.ToString() | Out-File -FilePath (Join-Path $analysisOut 'index.md') -Encoding utf8

    # --- status (stdout + file) ---
    $status = @{
        status = 'ok'
        message = "Analysis inputs ready for '$displayName'. Read .analysis/index.json then author the report."
        app = $displayName
        appFolder = $safeName
        outputDir = (Resolve-Path $appOut).Path
        files = @{
            index = '.analysis/index.json'
            digest = '.analysis/index.md'
            mechanicalFindings = '.analysis/mechanical-findings.json'
            enumeration = '.analysis/enumeration.md'
            summary = '.analysis/summary.md'
            src = 'src'
            report = "$safeName.analysis.md"
        }
        counts = @{
            screens=$screenNames.Count; controls=$controls.Count; dataSources=$dataSources.Count
            deterministicFindings=$det.Count; leads=$leads.Count
        }
    }
    Write-Status -StatusFilePath (Join-Path $analysisOut 'status.json') -Obj $status
    exit 0
}
catch {
    Write-Status -Obj @{ status='error'; message=("Analyzer failed: " + $_.Exception.Message); detail=($_.ScriptStackTrace) }
    exit 0
}
finally {
    if ($work -and (Test-Path $work)) { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }
}
