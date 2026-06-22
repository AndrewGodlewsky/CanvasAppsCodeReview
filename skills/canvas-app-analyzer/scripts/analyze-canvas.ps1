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
# Get-Levenshtein: standard edit distance between two strings.
# Uses a two-row rolling array to keep memory O(min(|a|,|b|)) rather than O(|a|*|b|).
# No external modules — pure PowerShell dynamic programming.
# ---------------------------------------------------------------------------
function Get-Levenshtein([string]$a, [string]$b) {
    $la = $a.Length; $lb = $b.Length
    if ($la -eq 0) { return $lb }
    if ($lb -eq 0) { return $la }
    # Ensure $a is the shorter string so the rolling array is small.
    if ($la -gt $lb) { $tmp = $a; $a = $b; $b = $tmp; $tmp = $la; $la = $lb; $lb = $tmp }
    $prev = [int[]]::new($la + 1)
    $curr = [int[]]::new($la + 1)
    for ($j = 0; $j -le $la; $j++) { $prev[$j] = $j }
    for ($i = 1; $i -le $lb; $i++) {
        $curr[0] = $i
        for ($j = 1; $j -le $la; $j++) {
            $cost = if ($b[$i - 1] -eq $a[$j - 1]) { 0 } else { 1 }
            $del  = $prev[$j]     + 1
            $ins  = $curr[$j - 1] + 1
            $sub  = $prev[$j - 1] + $cost
            $mn   = if ($del -lt $ins) { $del } else { $ins }
            $curr[$j] = if ($sub -lt $mn) { $sub } else { $mn }
        }
        $tmp = $prev; $prev = $curr; $curr = $tmp
    }
    return $prev[$la]
}

# ---------------------------------------------------------------------------
# Get-MaxIfDepth: return the maximum If/Switch nesting depth in a CODE span.
# Used by MC (Task 18) and optionally by DI (Task 19).
# Algorithm: walk character-by-character; track overall paren depth and a
# stack of "If/Switch frame" paren depths.  When we see the token "If(" or
# "Switch(" we push the current paren depth onto the If/Switch stack and
# increment paren depth; when overall paren depth drops back to the level
# at the top of the stack we pop that frame.  Max stack size = max nesting.
# Requires the CODE span (string literals already blanked) so only code-
# level If( / Switch( calls are matched — not tokens inside string values.
# ---------------------------------------------------------------------------
function Get-MaxIfDepth([string]$Code) {
    if ($null -eq $Code -or $Code.Length -eq 0) { return 0 }
    $maxDepth   = 0
    $parenDepth = 0           # overall paren nesting (all ( ) pairs)
    $ifStack    = New-Object System.Collections.Generic.Stack[int]  # paren depths of open If/Switch frames
    $n          = $Code.Length
    $i          = 0

    while ($i -lt $n) {
        # Check for If( or Switch( token starting at position $i.
        # Power Fx allows optional whitespace between the keyword and '(', e.g. "If (" or "If  (".
        # Word-boundary guard: the char BEFORE "If"/"Switch" must NOT be an identifier char or '_'.
        $isIfToken = $false
        $tokenAdvance = 0   # how many chars to advance past the keyword (before the optional spaces + '(')

        if ($i + 1 -lt $n -and $Code[$i] -eq 'I' -and $Code[$i+1] -eq 'f') {
            # Candidate: check word boundary
            if ($i -eq 0 -or (-not [char]::IsLetterOrDigit($Code[$i-1]) -and $Code[$i-1] -ne '_')) {
                $tokenAdvance = 2   # length of "If"
            }
        }
        elseif ($i + 5 -lt $n -and $Code.Substring($i,6) -eq 'Switch') {
            if ($i -eq 0 -or (-not [char]::IsLetterOrDigit($Code[$i-1]) -and $Code[$i-1] -ne '_')) {
                $tokenAdvance = 6   # length of "Switch"
            }
        }

        if ($tokenAdvance -gt 0) {
            # Scan past the keyword, then past any whitespace, to see if a '(' follows
            $j = $i + $tokenAdvance
            while ($j -lt $n -and ($Code[$j] -eq ' ' -or $Code[$j] -eq "`t")) { $j++ }
            if ($j -lt $n -and $Code[$j] -eq '(') {
                $isIfToken = $true
                $i = $j   # position $i now points at '(' — processed in the block below
            }
        }

        $ch = $Code[$i]
        if ($ch -eq '(') {
            $parenDepth++
            if ($isIfToken) {
                # This '(' opens an If/Switch call; record current depth as frame marker
                [void]$ifStack.Push($parenDepth)
                $depth = $ifStack.Count
                if ($depth -gt $maxDepth) { $maxDepth = $depth }
            }
        }
        elseif ($ch -eq ')') {
            # Pop any If/Switch frames whose opening paren depth equals current parenDepth
            while ($ifStack.Count -gt 0 -and $ifStack.Peek() -eq $parenDepth) {
                [void]$ifStack.Pop()
            }
            if ($parenDepth -gt 0) { $parenDepth-- }
        }
        $i++
    }
    return $maxDepth
}

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
                deepNesting    = [bool]($sf | Where-Object { [System.Text.Encoding]::UTF8.GetByteCount($_.text) -gt $T_LongFormulaBytes })
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

    # --- Inconsistent naming (IN) - Low, enumeration, Confirmed ---
    # Category-level detector: fires when a variable/collection scope category MIXES
    # conventionally-prefixed names with un-prefixed names.  Requires at least one
    # compliant member (correct prefix) AND at least one violating member (wrong/no prefix)
    # within the same category.  Controls are excluded (too fuzzy -> false positives).
    # One finding per inconsistent category; VP fires per-instance (both may coexist).
    # Citation: coding-standards-and-performance.md section 1 (Naming & maintainability)
    # - https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability
    $inCitation = 'coding-standards-and-performance.md section 1 (Naming & maintainability / Inconsistent naming) - https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability'

    # Category definitions: [label, prefix, members-list]
    # Process in sorted order for deterministic id assignment.
    $inCategories = @(
        [pscustomobject]@{
            label    = 'collection'
            prefix   = 'col'
            members  = @($collectionList | ForEach-Object { $_.name })
            sortKey  = 'IN|collection'
        },
        [pscustomobject]@{
            label    = 'context variable'
            prefix   = 'loc'
            members  = @($variables | Where-Object { $_.scope -eq 'context' } | ForEach-Object { $_.name })
            sortKey  = 'IN|context'
        },
        [pscustomobject]@{
            label    = 'global variable'
            prefix   = 'gbl'
            members  = @($variables | Where-Object { $_.scope -eq 'global' } | ForEach-Object { $_.name })
            sortKey  = 'IN|global'
        }
    )

    foreach ($cat in ($inCategories | Sort-Object sortKey)) {
        $catMembers = $cat.members
        if ($catMembers.Count -lt 2) { continue }  # need at least 2 members to have both compliant and violating

        $compliant  = @($catMembers | Where-Object { $_ -clike ($cat.prefix + '*') })
        $violating  = @($catMembers | Where-Object { -not ($_ -clike ($cat.prefix + '*')) })

        # Only fire when BOTH compliant and violating members exist (mixed category)
        if ($compliant.Count -lt 1 -or $violating.Count -lt 1) { continue }

        $violatingStr = ($violating | Sort-Object) -join ', '
        $compliantStr = ($compliant | Sort-Object | Select-Object -First 3) -join ', '
        if ($compliant.Count -gt 3) { $compliantStr += ", ..." }

        $evid = "Inconsistent $($cat.label) naming: $($violating.Count) without '$($cat.prefix)' prefix ($violatingStr) vs $($compliant.Count) with prefix ($compliantStr)"
        $msg  = "$($cat.label) naming is inconsistent: $($violating.Count) name(s) lack the '$($cat.prefix)' prefix ($violatingStr) while $($compliant.Count) name(s) correctly use it ($compliantStr). Adopt the '$($cat.prefix)' prefix consistently so variables can be located by prefix search."

        [void]$det.Add((New-Finding -Prefix 'IN' -Type 'inconsistent-naming' `
            -Category 'Maintainability & naming' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
            -Citation $inCitation `
            -Location @{ screen=$null; control=$null; property=$null; file=$null; line=$null } `
            -Evidence $evid `
            -Message $msg `
            -SortKey $cat.sortKey))
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
    # Unreferenced controls (Potential) — behavior-aware per-control verdicts (D5)
    # Citation: coding-standards-and-performance.md section 3 (Dead/unused controls)
    # - https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability
    $urCitation = 'coding-standards-and-performance.md section 3 (Dead/unused controls) - https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability'

    # Known names that could appear in data-bound formulas: data sources, variables, collections,
    # and component custom property names (bare tokens inside component formulas).
    $knownDataNames = @(
        @($dataSources | ForEach-Object { $_.name }) +
        @($globals.Keys) +
        @($contexts.Keys) +
        @($collections.Keys) +
        @($compCustomProps | ForEach-Object { $_.propName })
    )

    foreach ($c in $controls) {
        if ($c.type -imatch 'Screen') { continue }
        $refs = ([regex]::Matches($allText, '(?<![\w.])' + [regex]::Escape($c.name) + '(?:\.|\b)')).Count
        if ($refs -gt 0) { continue }   # referenced — skip

        # Gather all formula records for this control
        $ctrlFms = @($formulas | Where-Object { $_.screen -eq $c.screen -and $_.control -eq $c.name })

        # Signal 1: hasHandler — owns any OnXxx event with a non-false formula
        $hasHandler = $false
        foreach ($fm in ($ctrlFms | Where-Object { $_.property -match '^On[A-Z]' })) {
            $norm = ($fm.text -replace '^=','').Trim()
            if ($norm -ine 'false') { $hasHandler = $true; break }
        }

        # Signal 2: dataBound — owns Items/DataSource/Default/Text/Value whose formula
        # references a known data source, variable, collection, or component custom property
        # (not a static string literal like ="hello").
        $dataBound = $false
        $dataBoundReason = ''
        foreach ($fm in ($ctrlFms | Where-Object { $_.property -in @('Items','DataSource','Default','Text','Value') })) {
            $fmCode = (Split-FormulaSpans $fm.text).Code
            foreach ($dn in $knownDataNames) {
                if ([string]::IsNullOrWhiteSpace($dn)) { continue }
                if ([regex]::IsMatch($fmCode, '(?<![.\w])' + [regex]::Escape($dn) + '\b')) {
                    $dataBound = $true
                    $dataBoundReason = "surfaces data via $($fm.property)"
                    break
                }
            }
            if ($dataBound) { break }
        }

        # Signal 3: visibleByDefault — does NOT have Visible = false
        $visibleByDefault = $true
        $visFm = $ctrlFms | Where-Object { $_.property -ieq 'Visible' } | Select-Object -First 1
        if ($visFm) {
            $normVis = ($visFm.text -replace '^=','').Trim()
            if ($normVis -ine 'false') { $visibleByDefault = $true } else { $visibleByDefault = $false }
        }
        # No Visible property = visible by default (true stays)

        # Compute verdict
        $verdict = $null
        $reasons = @()
        if (-not $hasHandler -and -not $dataBound -and -not $visibleByDefault) {
            $verdict = 'strong-dead-candidate'
            $urMsg = "Control '$($c.name)' is never referenced by any formula and has no active event handler, no data binding, and is permanently hidden - very likely dead weight. Remove or document."
        } else {
            $verdict = 'likely-decorative-or-layout'
            if ($visibleByDefault) { $reasons += 'visible' }
            if ($hasHandler)       { $reasons += 'has live event handler' }
            if ($dataBound)        { $reasons += $dataBoundReason }
            $reasonStr = $reasons -join '; '
            $urMsg = "Control '$($c.name)' is never referenced by any formula but may be intentional ($reasonStr). Verify it is not dead (decorative/layout controls are fine unreferenced)."
        }

        [void]$det.Add((New-Finding -Prefix 'UR' -Type 'unreferenced-control' `
            -Category 'Dead / unused' -Severity 'Low' -Confidence 'Potential' -Tier 'enumeration' `
            -Citation $urCitation `
            -Verdict $verdict `
            -Location @{ screen=$c.screen; control=$c.name; property=$null; file=$c.file; line=$c.line } `
            -Evidence "$($c.name) ($($c.type))" `
            -Message $urMsg `
            -SortKey "$($c.file)|$($c.line)|$($c.name)"))
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

    # --- Missing comment on complex formula (MC) - Low, enumeration, Confirmed ---
    # A formula is COMPLEX if: its UTF-8 byte count > $T_LongFormulaBytes  OR
    #   the maximum If/Switch nesting depth in its CODE span >= $T_DeepIfDepth.
    # A complex formula that has NO explanatory comment in its CODE span fires MC.
    # "No comment" = CODE span contains neither "//" nor "/*".
    # Formulas with a comment (even prose-only) do NOT fire MC (CC/MC non-contradiction, DoD #12).
    # Citation: coding-standards-and-performance.md section 1 (Comments)
    # - https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability
    $mcCitation = 'coding-standards-and-performance.md section 1 (Comments) - https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability'
    foreach ($fm in $formulas) {
        $byteCount = [System.Text.Encoding]::UTF8.GetByteCount($fm.text)
        $spans     = Split-FormulaSpans $fm.text
        $codeText  = $spans.Code

        # Complexity check: long (byte count) OR deep If/Switch nesting
        $isLong  = ($byteCount -gt $T_LongFormulaBytes)
        $ifDepth = Get-MaxIfDepth $codeText
        $isDeep  = ($ifDepth -ge $T_DeepIfDepth)
        if (-not $isLong -and -not $isDeep) { continue }

        # Comment check: any "//" or "/*" present in the CODE span
        $hasComment = ($codeText -match '//') -or ($codeText -match '/\*')
        if ($hasComment) { continue }   # has a comment → does NOT fire MC

        $reasonParts = @()
        if ($isDeep)  { $reasonParts += "If/Switch nesting depth $ifDepth (threshold: $T_DeepIfDepth)" }
        if ($isLong)  { $reasonParts += "$byteCount bytes (threshold: $T_LongFormulaBytes)" }
        $reason = $reasonParts -join '; '

        [void]$det.Add((New-Finding -Prefix 'MC' -Type 'missing-comment-complex-formula' `
            -Category 'Maintainability & naming' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
            -Citation $mcCitation `
            -Location @{ screen=$fm.screen; control=$fm.control; property=$fm.property; file=$fm.file; line=$fm.line } `
            -Evidence "$($fm.control).$($fm.property): $reason" `
            -Message "Complex formula '$($fm.control).$($fm.property)' has no explanatory comment ($reason). Add a // or /* */ comment to document the intent of non-obvious logic." `
            -SortKey "$($fm.file)|$($fm.line)|$($fm.control).$($fm.property)"))
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

    # --- Duplicate / redundant controls (DC) - Medium, narrative, Confirmed ---
    # Detects copy-paste control duplication: two or more controls of the same type whose
    # complete property set (type + sorted propName=normalizedText pairs) is identical.
    # A signature requires >=1 property so bare controls with no properties don't falsely collapse.
    # Emits ONE finding per duplicate group listing all members.
    # Citation: coding-standards-and-performance.md §2 (duplicated formulas/layouts) + §5 (Components)
    $dcCitation = 'coding-standards-and-performance.md section 2 (Duplicate/redundant controls) + section 5 (Components & reuse) - https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps'
    $dcSigMap = @{}   # signature -> list of {name, file, line}
    foreach ($c in $controls) {
        # Gather all properties for this control (screen+name match)
        $ctrlFormulas = @($formulas | Where-Object { $_.screen -eq $c.screen -and $_.control -eq $c.name })
        if ($ctrlFormulas.Count -lt 1) { continue }   # no properties → skip (avoids bare-control false groups)
        # Build sorted prop=normalizedText pairs
        $pairs = @($ctrlFormulas | ForEach-Object {
            $norm = ($_.text -replace '\s+',' ').Trim()
            "$($_.property)=$norm"
        } | Sort-Object)
        $sig = "$($c.type)|" + ($pairs -join '|')
        if (-not $dcSigMap.ContainsKey($sig)) { $dcSigMap[$sig] = New-Object System.Collections.ArrayList }
        [void]$dcSigMap[$sig].Add([pscustomobject]@{ name=$c.name; file=$c.file; line=$c.line; screen=$c.screen })
    }
    foreach ($sig in $dcSigMap.Keys) {
        $grp = $dcSigMap[$sig]
        if ($grp.Count -ge 2) {
            $first = $grp[0]
            $memberList = @($grp | ForEach-Object { "$($_.name) ($($_.file):$($_.line))" })
            $evid = "Duplicate controls ($($grp.Count)): " + ($memberList -join '; ')
            $msg  = "$($grp.Count) controls share an identical type and property set (likely copy-paste): " +
                    ($memberList -join '; ') +
                    ". Extract the repeated layout into a Canvas Component with input properties for the differing parts."
            [void]$det.Add((New-Finding -Prefix 'DC' -Type 'duplicate-control' `
                -Category 'Redundancy & reuse' -Severity 'Medium' -Confidence 'Confirmed' -Tier 'narrative' `
                -Citation $dcCitation `
                -Location @{ screen=$first.screen; control=$first.name; property=$null; file=$first.file; line=$first.line } `
                -Evidence $evid `
                -Message $msg `
                -SortKey $sig))
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

    # --- Long formulas (LF) - Medium, narrative, Confirmed ---
    # A single property formula whose UTF-8 byte count exceeds $T_LongFormulaBytes is flagged.
    # Long formulas hurt readability and Studio performance. Split into With() subexpressions
    # or named formulas (App.Formulas).
    # Citation: coding-standards-and-performance.md §2 "Formula formatting" + "Split long formulas"
    $lfCitation = 'coding-standards-and-performance.md section 2 (Formula formatting / Split long formulas) - https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability'
    foreach ($fm in $formulas) {
        $byteCount = [System.Text.Encoding]::UTF8.GetByteCount($fm.text)
        if ($byteCount -gt $T_LongFormulaBytes) {
            $snipLen = [Math]::Min(120, $fm.text.Length)
            $snipSuffix = if ($fm.text.Length -gt $snipLen) { ' ...' } else { '' }
            $snip = $fm.text.Substring(0, $snipLen) + $snipSuffix
            [void]$det.Add((New-Finding -Prefix 'LF' -Type 'long-formula' `
                -Category 'Maintainability & naming' -Severity 'Medium' -Confidence 'Confirmed' -Tier 'narrative' `
                -Citation $lfCitation `
                -Location @{ screen=$fm.screen; control=$fm.control; property=$fm.property; file=$fm.file; line=$fm.line } `
                -Evidence "$byteCount bytes: $snip" `
                -Message "Formula '$($fm.control).$($fm.property)' is $byteCount bytes (threshold: $T_LongFormulaBytes). Split into With() subexpressions or extract to App.Formulas named formulas to improve readability and Studio performance." `
                -SortKey "$($fm.file)|$($fm.line)|$($fm.control).$($fm.property)"))
        }
    }

    # --- Deep If/Switch nesting (DI) - Medium, narrative, Confirmed ---
    # A formula whose maximum If/Switch nesting depth in its CODE span meets or exceeds
    # $T_DeepIfDepth is flagged.  Deeply nested conditionals hurt readability and are
    # better expressed with With() scoped values, Switch, or App.Formulas named formulas.
    # Reuses Get-MaxIfDepth (added in Task 18) — no duplicate depth logic.
    # Citation: coding-standards-and-performance.md §2 "With function" +
    #   efficient-calculations: https://learn.microsoft.com/power-apps/maker/canvas-apps/efficient-calculations
    $diCitation = 'coding-standards-and-performance.md section 2 (With function / Deep If/Switch nesting) - https://learn.microsoft.com/power-apps/maker/canvas-apps/efficient-calculations'
    foreach ($fm in $formulas) {
        $spans    = Split-FormulaSpans $fm.text
        $codeText = $spans.Code
        $ifDepth  = Get-MaxIfDepth $codeText
        if ($ifDepth -lt $T_DeepIfDepth) { continue }
        $snipLen    = [Math]::Min(120, $fm.text.Length)
        $snipSuffix = if ($fm.text.Length -gt $snipLen) { ' ...' } else { '' }
        $snip       = $fm.text.Substring(0, $snipLen) + $snipSuffix
        [void]$det.Add((New-Finding -Prefix 'DI' -Type 'deep-if-nesting' `
            -Category 'Maintainability & naming' -Severity 'Medium' -Confidence 'Confirmed' -Tier 'narrative' `
            -Citation $diCitation `
            -Location @{ screen=$fm.screen; control=$fm.control; property=$fm.property; file=$fm.file; line=$fm.line } `
            -Evidence "$($fm.control).$($fm.property): If/Switch nesting depth $ifDepth (threshold: $T_DeepIfDepth)" `
            -Message "Formula '$($fm.control).$($fm.property)' has If/Switch nesting depth $ifDepth (threshold: $T_DeepIfDepth). Break the nested chain into a With() scoped expression, a Switch on a shared condition, or named formulas (App.Formulas) to improve readability and maintainability." `
            -SortKey "$($fm.file)|$($fm.line)|$($fm.control).$($fm.property)"))
    }

    # --- Near-duplicate formulas (ND) - Medium, narrative, Confirmed ---
    # Detects pairs of formulas that are likely copy-paste with small edits (near-dups),
    # distinct from exact duplicates (XD).  Algorithm:
    #   1. STRUCT-NORMALIZE each formula: lowercase, collapse whitespace, trim, blank
    #      string-literal contents via Split-FormulaSpans (so formulas differing ONLY in
    #      string values become structurally identical — still a near-dup worth flagging).
    #   2. Only consider formulas whose struct-normalized length >= $T_NearDupMinLen (60).
    #   3. For each pair within a length bucket (the two lengths within ±15%):
    #      - SKIP if raw whitespace-collapsed texts are IDENTICAL (that's XD's job).
    #      - Compute Levenshtein ratio = 1 - (distance / max(lenA, lenB)).
    #      - If ratio >= $T_NearDupRatio (0.90) → the pair is a near-dup.
    #   4. CLUSTER pairs transitively; emit ONE finding per cluster.
    # Citation: coding-standards-and-performance.md §2 Redundancy (near-duplicate logic →
    #   extract to named formula/component) — general maintainability guidance.
    $ndCitation = 'coding-standards-and-performance.md section 2 (Redundancy / Near-duplicate formulas) - general maintainability guidance: extract to a named formula (App.Formulas) or Canvas Component to eliminate near-duplicate logic'

    # Build struct-normalized representations for each formula record.
    # structNorm = lowercase + collapse whitespace + blank string-literal contents.
    $ndRecords = New-Object System.Collections.ArrayList
    foreach ($fm in $formulas) {
        $spans = Split-FormulaSpans $fm.text
        # Blank string-literal contents: replace each literal's content with a fixed placeholder.
        # Split-FormulaSpans returns Code where each "..." span is replaced with spaces of the
        # same byte length, preserving column positions. We use the Code span directly as the
        # struct-normalized base (string contents are already blanked to spaces).
        $structNorm = ($spans.Code.ToLowerInvariant() -replace '\s+',' ').Trim()
        if ($structNorm.Length -lt $T_NearDupMinLen) { continue }
        # Raw collapsed text (for exact-dup skip guard)
        $rawCollapsed = ($fm.text -replace '\s+',' ').Trim()
        [void]$ndRecords.Add([pscustomobject]@{
            fm          = $fm
            structNorm  = $structNorm
            rawCollapsed= $rawCollapsed
            structLen   = $structNorm.Length
        })
    }

    # Find near-dup pairs using length bucketing (only compare pairs within ±15% length).
    # Union-Find for transitive clustering.
    $ndCount = $ndRecords.Count
    $ndParent = [int[]]::new($ndCount)
    for ($i = 0; $i -lt $ndCount; $i++) { $ndParent[$i] = $i }

    function _NdFind([int[]]$parent, [int]$x) {
        while ($parent[$x] -ne $x) { $parent[$x] = $parent[$parent[$x]]; $x = $parent[$x] }
        return $x
    }
    function _NdUnion([int[]]$parent, [int]$x, [int]$y) {
        $rx = _NdFind $parent $x; $ry = _NdFind $parent $y
        if ($rx -ne $ry) { $parent[$rx] = $ry }
    }

    for ($i = 0; $i -lt $ndCount - 1; $i++) {
        $recA = $ndRecords[$i]
        for ($j = $i + 1; $j -lt $ndCount; $j++) {
            $recB = $ndRecords[$j]
            # Length bucket guard: skip if lengths differ by more than 15%
            $maxLen = [Math]::Max($recA.structLen, $recB.structLen)
            $minLen = [Math]::Min($recA.structLen, $recB.structLen)
            if ($minLen -lt ($maxLen * 0.85)) { continue }
            # Skip if raw-collapsed texts are identical (exact duplicate → XD's job)
            if ($recA.rawCollapsed -ceq $recB.rawCollapsed) { continue }
            # Compute Levenshtein ratio on struct-normalized strings
            $dist  = Get-Levenshtein $recA.structNorm $recB.structNorm
            $ratio = 1.0 - ($dist / $maxLen)
            if ($ratio -ge $T_NearDupRatio) {
                _NdUnion $ndParent $i $j
            }
        }
    }

    # Collect clusters: group record indices by their root in the union-find.
    $ndClusters = @{}
    for ($i = 0; $i -lt $ndCount; $i++) {
        $root = _NdFind $ndParent $i
        if (-not $ndClusters.ContainsKey($root)) { $ndClusters[$root] = New-Object System.Collections.ArrayList }
        [void]$ndClusters[$root].Add($i)
    }

    # Sort cluster roots so emission order into $det is deterministic across runs
    # (hashtable .Keys order is not guaranteed in PS 5.1). IDs are re-sorted by sortKey in
    # Stamp-Ids regardless, but this keeps the emitted JSON/enumeration row order stable too.
    foreach ($root in ($ndClusters.Keys | Sort-Object)) {
        $idxList = $ndClusters[$root]
        if ($idxList.Count -lt 2) { continue }   # singleton → no near-dup
        # Sort members deterministically: file then line then control.property
        $members = @($idxList | ForEach-Object { $ndRecords[$_] } | Sort-Object {
            "$($_.fm.file)|$($_.fm.line)|$($_.fm.control).$($_.fm.property)"
        })
        $first = $members[0].fm
        $memberList = @($members | ForEach-Object { "$($_.fm.control).$($_.fm.property) ($($_.fm.file):$($_.fm.line))" })
        $sortKey    = ($memberList | Sort-Object) -join '|'
        $evid = "Near-duplicate formulas ($($members.Count)): " + ($memberList -join '; ')
        $msg  = "$($members.Count) formulas are near-duplicates (likely copy-paste with small edits): " +
                ($memberList -join '; ') +
                ". Extract the shared logic to a named formula (App.Formulas) or a Canvas Component with input properties for the differing parts."
        [void]$det.Add((New-Finding -Prefix 'ND' -Type 'near-duplicate-formula' `
            -Category 'Redundancy & reuse' -Severity 'Medium' -Confidence 'Confirmed' -Tier 'narrative' `
            -Citation $ndCitation `
            -Location @{ screen=$first.screen; control=$first.control; property=$first.property; file=$first.file; line=$first.line } `
            -Evidence $evid `
            -Message $msg `
            -SortKey $sortKey))
    }

    # ============================================================================
    # MAGIC LITERALS: reusable extraction (consumed by MV here; RL/EV in Tasks 22-23)
    # ============================================================================
    # Build a flat list of every hardcoded literal occurrence across all formulas.
    # Each record: { value, kind('string'|'number'), file, line, screen, control, property }
    # String literals: every non-empty entry from Split-FormulaSpans .Strings.
    # Numeric literals: numbers in the .Code span whose |value| is not in {0, 1}.
    #   RGBA/ColorValue argument spans are removed from the code text before scanning
    #   so color-component numbers (e.g. RGBA(255,0,128,1)) are not flagged.
    $magicLiterals = New-Object System.Collections.ArrayList
    $mvNumPattern  = [regex]::new('(?<![\w.])-?\d+(\.\d+)?')
    $mvRgbaPattern = [regex]::new('(?i)\b(?:RGBA|ColorValue)\s*\([^)]*\)')

    foreach ($fm in $formulas) {
        $spans    = Split-FormulaSpans $fm.text
        $location = @{
            file     = $fm.file
            line     = $fm.line
            screen   = $fm.screen
            control  = $fm.control
            property = $fm.property
        }

        # STRING literals: each non-empty string from the span extractor
        foreach ($s in $spans.Strings) {
            if ([string]::IsNullOrEmpty($s)) { continue }
            [void]$magicLiterals.Add([pscustomobject](@{ value=$s; kind='string' } + $location))
        }

        # NUMERIC literals: scan the code span with RGBA/ColorValue spans removed
        $codeForNums = $mvRgbaPattern.Replace($spans.Code, ' ')
        foreach ($m in $mvNumPattern.Matches($codeForNums)) {
            $numVal = [double]$m.Value
            $absVal = [Math]::Abs($numVal)
            if ($absVal -eq 0 -or $absVal -eq 1) { continue }   # trivial exclusions
            [void]$magicLiterals.Add([pscustomobject](@{ value=$m.Value; kind='number' } + $location))
        }
    }

    # --- Magic values (MV) - Low, enumeration, Confirmed ---
    # Each magic literal occurrence is its own MV finding.
    # Citation: coding-standards-and-performance.md §1 "Code readability" —
    #   Magic values: centralize hardcoded literals into named formulas (App.Formulas)
    #   or named constants (global variables set once in App.OnStart).
    # - https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability
    $mvCitation = 'coding-standards-and-performance.md section 1 (Code readability / Magic values) - centralize hardcoded literals into named formulas (App.Formulas) or constants: https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability'
    # $mvOrd disambiguates the sortKey when the SAME literal value appears twice at the
    # same file/line/control/property (e.g. If(x, "retry", "retry")) so each occurrence
    # still gets a unique, stable id. $magicLiterals build order is deterministic.
    $mvOrd = 0
    foreach ($lit in $magicLiterals) {
        $mvOrd++
        $kindLabel = $lit.kind
        $evid = $lit.value
        $msg  = "Magic $kindLabel literal $($lit.value) in $($lit.control).$($lit.property). Consider extracting to a named formula (App.Formulas) or a named constant so the value is centralized and self-documenting."
        [void]$det.Add((New-Finding -Prefix 'MV' -Type 'magic-value' `
            -Category 'Maintainability & naming' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
            -Citation $mvCitation `
            -Location @{ screen=$lit.screen; control=$lit.control; property=$lit.property; file=$lit.file; line=$lit.line } `
            -Evidence $evid `
            -Message $msg `
            -SortKey ("{0}|{1}|{2}.{3}|{4}|{5:D5}" -f $lit.file,$lit.line,$lit.control,$lit.property,$lit.value,$mvOrd)))
    }

    # --- Repeated literals (RL) - Medium, narrative, Confirmed ---
    # A literal value (string or number) that appears in >= $T_RepeatedLiteralMin DISTINCT
    # formulas is a centralization candidate: the constant should live in App.Formulas or
    # a named global so every consumer references the name, not the value.
    # "Distinct formulas" = distinct (file, line) pairs from $magicLiterals.
    # Emits ONE finding per repeated value listing all locations (file:line).
    # Emission order is deterministic: grouped values sorted before processing.
    # Citation: coding-standards-and-performance.md §1 §2 (Repeated literals) — general
    #   maintainability guidance: centralize repeated constants into a named formula
    #   (App.Formulas) so changes propagate automatically:
    #   https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability
    $rlCitation = 'coding-standards-and-performance.md section 1/2 (Repeated literals) - centralize repeated constants into a named formula (App.Formulas): https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability'

    # Group $magicLiterals by value; count distinct (file|line) keys per group.
    $rlByValue = @{}
    foreach ($lit in $magicLiterals) {
        $v = $lit.value
        if (-not $rlByValue.ContainsKey($v)) { $rlByValue[$v] = New-Object System.Collections.ArrayList }
        [void]$rlByValue[$v].Add($lit)
    }

    # Process groups in sorted-value order for deterministic output.
    foreach ($v in ($rlByValue.Keys | Sort-Object)) {
        $group = $rlByValue[$v]
        # Count DISTINCT formulas by unique file|line key
        $distinctKeys = @($group | ForEach-Object { "$($_.file)|$($_.line)" } | Sort-Object -Unique)
        if ($distinctKeys.Count -lt $T_RepeatedLiteralMin) { continue }

        # Build the location list from the first occurrence per distinct key, sorted.
        $sortedLocs = @($group | Sort-Object @{e={$_.file}},@{e={[int]$_.line}} |
            ForEach-Object { "$($_.file):$($_.line)" } | Select-Object -Unique)
        $locStr  = $sortedLocs -join '; '
        $kindLabel = ($group[0].kind)
        $evid = "Value $v ($kindLabel) in $($distinctKeys.Count) formulas: $locStr"
        $msg  = "Literal $v ($kindLabel) is hardcoded in $($distinctKeys.Count) distinct formulas ($locStr). Centralize it as a named formula in App.Formulas or a constant set in App.OnStart so changes propagate automatically."

        [void]$det.Add((New-Finding -Prefix 'RL' -Type 'repeated-literal' `
            -Category 'Maintainability & naming' -Severity 'Medium' -Confidence 'Confirmed' -Tier 'narrative' `
            -Citation $rlCitation `
            -Location @{ screen=$group[0].screen; control=$group[0].control; property=$group[0].property; file=$group[0].file; line=$group[0].line } `
            -Evidence $evid `
            -Message $msg `
            -SortKey "RL|$v"))
    }

    # --- Environment-specific hardcoding (EV) - High, narrative, Confirmed ---
    # Flags string literals that embed environment-specific values: absolute URLs, GUIDs,
    # SharePoint/Dynamics hostnames. These silently break when the app is deployed to another
    # environment. Each occurrence gets its own EV finding (one per env-specific string, per location).
    # Note: EV and MV both fire on the same URL string — intentional (different lenses/severity).
    # Citation: coding-standards-and-performance.md §6 (Environment-specific values) —
    #   use Power Apps environment variables instead of hardcoded URLs/GUIDs/hostnames:
    #   https://learn.microsoft.com/power-apps/maker/data-platform/environmentvariables
    $evCitation = 'coding-standards-and-performance.md section 6 (Environment-specific values / High) - replace hardcoded URLs, GUIDs, and hostnames with Power Apps environment variables: https://learn.microsoft.com/power-apps/maker/data-platform/environmentvariables'

    $evPatterns = @(
        [regex]::new('https?://', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase),
        # Hex boundaries so a GUID-shaped substring of a longer hex run (e.g. a 40-char hash) is not mis-flagged.
        [regex]::new('(?<![0-9a-fA-F])[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(?![0-9a-fA-F])'),
        [regex]::new('\.sharepoint\.(com|test)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase),
        [regex]::new('\.crm\d*\.dynamics\.com', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    )

    $evOrd = 0
    # Process only string-kind entries from $magicLiterals (env-specific patterns are string values)
    foreach ($lit in ($magicLiterals | Where-Object { $_.kind -eq 'string' })) {
        $isEnvSpecific = $false
        $matchedReason = ''
        foreach ($pat in $evPatterns) {
            if ($pat.IsMatch($lit.value)) {
                $isEnvSpecific = $true
                $matchedReason = $pat.ToString()
                break
            }
        }
        if (-not $isEnvSpecific) { continue }

        $evOrd++
        $msg = "Environment-specific string literal '$($lit.value)' hardcoded in $($lit.control).$($lit.property). This value will silently break when the app is deployed to another environment. Replace it with a Power Apps environment variable."
        [void]$det.Add((New-Finding -Prefix 'EV' -Type 'env-specific-hardcoding' `
            -Category 'Maintainability & naming' -Severity 'High' -Confidence 'Confirmed' -Tier 'narrative' `
            -Citation $evCitation `
            -Location @{ screen=$lit.screen; control=$lit.control; property=$lit.property; file=$lit.file; line=$lit.line } `
            -Evidence $lit.value `
            -Message $msg `
            -SortKey ("{0}|{1}|{2}.{3}|{4}|{5:D5}" -f $lit.file,$lit.line,$lit.control,$lit.property,$lit.value,$evOrd)))
    }

    # --- God screens (GS) - Medium, narrative, Confirmed ---
    # A screen with too many controls OR too much formula weight is a god screen that
    # should be decomposed into components, nested galleries, or split across screens.
    # Iterates $screenInfo (screens only — App and components are excluded by construction).
    # Citation: coding-standards-and-performance.md §5 (God screens) —
    #   Build large & complex canvas apps:
    #   https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps
    $gsCitation = 'coding-standards-and-performance.md section 5 (God screens) - decompose into components/nested galleries; move logic to App.Formulas: https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps'
    foreach ($si in $screenInfo) {
        $isGodByControls = ($si.controlCount -gt $T_GodScreenControls)
        $isGodByBytes    = ($si.formulaBytes -gt $T_GodScreenBytes)
        if (-not $isGodByControls -and -not $isGodByBytes) { continue }

        $reasons = @()
        if ($isGodByControls) { $reasons += "$($si.controlCount) controls (threshold: $T_GodScreenControls)" }
        if ($isGodByBytes)    { $reasons += "$($si.formulaBytes) formula bytes (threshold: $T_GodScreenBytes)" }
        $reasonStr = $reasons -join '; '

        $evid = "Screen '$($si.name)': $reasonStr"
        $msg  = "Screen '$($si.name)' is a god screen ($reasonStr). Decompose it: extract repeated control groups into Canvas Components, use nested galleries/containers to reduce top-level control count, and move shared logic to App.Formulas named formulas."

        [void]$det.Add((New-Finding -Prefix 'GS' -Type 'god-screen' `
            -Category 'Maintainability & naming' -Severity 'Medium' -Confidence 'Confirmed' -Tier 'narrative' `
            -Citation $gsCitation `
            -Location @{ screen=$si.name; control=$null; property=$null; file=$si.file; line=1 } `
            -Evidence $evid `
            -Message $msg `
            -SortKey "$($si.file)|1|$($si.name)"))
    }

    # --- Deep control-tree nesting (CT) - Low, enumeration, Confirmed ---
    # A control whose nesting depth in the control tree meets or exceeds
    # $T_ControlTreeDepth is flagged. Deeply nested containers hurt render
    # performance and maintainability (working-with-large-apps guidance).
    # Reuses the `depth` and `ancestors` fields populated by the parser (Task 4).
    # Citation: coding-standards-and-performance.md §5 (Deep control-tree nesting) —
    #   Build large & complex canvas apps (deeply nested containers hurt render + maintainability):
    #   https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps
    $ctCitation = 'coding-standards-and-performance.md section 5 (Deep control-tree nesting) - deeply nested containers hurt render performance and maintainability; flatten by extracting to Canvas Components: https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps'
    foreach ($c in $controls) {
        if ($c.depth -lt $T_ControlTreeDepth) { continue }
        $ancestorStr = if ($c.ancestors -and $c.ancestors.Count -gt 0) { ' (ancestors: ' + ($c.ancestors -join ' > ') + ')' } else { '' }
        $evid = "depth $($c.depth)$ancestorStr"
        $msg  = "Control '$($c.name)' is nested $($c.depth) levels deep in the control tree (threshold: $T_ControlTreeDepth). Deeply nested containers slow rendering. Flatten the layout or extract the nested group into a Canvas Component."
        [void]$det.Add((New-Finding -Prefix 'CT' -Type 'deep-control-tree-nesting' `
            -Category 'Maintainability & naming' -Severity 'Low' -Confidence 'Confirmed' -Tier 'enumeration' `
            -Citation $ctCitation `
            -Location @{ screen=$c.screen; control=$c.name; property=$null; file=$c.file; line=$c.line } `
            -Evidence $evid `
            -Message $msg `
            -SortKey "$($c.file)|$($c.line)|$($c.name)"))
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

    # OG: overuse of globals (app-level lead, count-based trigger)
    # Scoped to count-based app-level lead only for full determinism.
    # Per-single-screen-global variant (a global read on exactly one screen may fit UpdateContext)
    # is intentionally excluded - judgment needed per variable, handled via the hint text.
    # Citation: s2 App.OnStart -> App.Formulas / With function guidance.
    $ogGlobalCount = $globals.Keys.Count
    if ($ogGlobalCount -gt $T_GlobalOveruse) {
        [void]$leads.Add((New-Lead -Kind 'overuse-of-globals' -Category 'Maintainability & naming' `
            -Screen 'App' -Control $null -Property $null -File $null -Line $null `
            -Snippet $null `
            -Hint ("$ogGlobalCount global variables declared (threshold: $T_GlobalOveruse). Consider whether some " +
                   "could be context variables (UpdateContext/loc) scoped to a single screen, or named formulas " +
                   "in App.Formulas (immutable, lazily evaluated, ~80% load win). " +
                   "See coding-standards-and-performance.md s2 (App.OnStart -> App.Formulas / With function). " +
                   "Judge per variable - not all globals are replaceable.")))
    }

    # --- XC: tight cross-screen coupling (lead, kind='cross-screen-coupling') ---
    # Detects a formula on one screen that references a control belonging to a DIFFERENT
    # screen via a property access (controlName.Property). Cross-screen control references
    # create tight coupling: renaming or moving the referenced control silently breaks the
    # formula, and the dependency is invisible from the referenced screen.
    # Citation: working-with-large-apps (decouple via variables/collections/named formulas)
    # https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps
    $xcCitation = 'coding-standards-and-performance.md section 5 (Tight cross-screen coupling) - decouple via global variables, collections, or named formulas (App.Formulas): https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps'

    # Build a control-name -> screen map (skip ambiguous duplicates).
    $xcCtrlMap = @{}   # name -> screen (or $null if ambiguous)
    foreach ($c in $controls) {
        if ($c.type -imatch 'Screen') { continue }   # skip screen-type pseudo-controls
        $n = $c.name
        if ($xcCtrlMap.ContainsKey($n)) {
            if ($xcCtrlMap[$n] -ne $c.screen) {
                $xcCtrlMap[$n] = $null   # ambiguous: same name on multiple screens - skip
            }
            # same screen: already recorded, leave as-is
        } else {
            $xcCtrlMap[$n] = $c.screen
        }
    }

    foreach ($fm in $formulas) {
        if ($compFiles.ContainsKey($fm.screen)) { continue }   # skip component formulas
        $spans    = Split-FormulaSpans $fm.text
        $codeText = $spans.Code

        # Scan the code span for <controlName>. references (word-boundary before name, dot after).
        # Track already-reported (formula, referencedControl) pairs so we emit at most ONE lead
        # per cross-screen reference per formula.
        $xcAlreadyReported = @{}
        foreach ($ctrlName in $xcCtrlMap.Keys) {
            $targetScreen = $xcCtrlMap[$ctrlName]
            if ($null -eq $targetScreen) { continue }      # ambiguous - skip
            if ($targetScreen -eq $fm.screen) { continue } # same screen - not XC

            # Match: word boundary before the control name, then a literal dot (property access)
            $pattern = '(?<![\w.])' + [regex]::Escape($ctrlName) + '\.'
            if (-not [regex]::IsMatch($codeText, $pattern)) { continue }

            # Deduplicate: only one lead per (formula-location, referenced-control) pair
            $dedupKey = "$($fm.file)|$($fm.line)|$($fm.control)|$ctrlName"
            if ($xcAlreadyReported.ContainsKey($dedupKey)) { continue }
            $xcAlreadyReported[$dedupKey] = $true

            $snipLen = [Math]::Min(200, $fm.text.Length)
            $snip    = $fm.text.Substring(0, $snipLen) + $(if ($fm.text.Length -gt $snipLen) { ' ...' } else { '' })
            $hint    = ("Cross-screen reference: $($fm.screen)/$($fm.control).$($fm.property) -> " +
                        "$targetScreen/$ctrlName. " +
                        "Referencing a control from another screen creates tight coupling: if $ctrlName " +
                        "is renamed or moved, this formula silently breaks. " +
                        "Decouple by storing the value in a global variable (Set), collection, or " +
                        "named formula (App.Formulas) that both screens can read. " +
                        "See $xcCitation")

            [void]$leads.Add((New-Lead -Kind 'cross-screen-coupling' -Category 'Maintainability & naming' `
                -Screen $fm.screen -Control $fm.control -Property $fm.property -File $fm.file -Line $fm.line `
                -Snippet $snip -Hint $hint))
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
