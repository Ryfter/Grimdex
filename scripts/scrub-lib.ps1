#!/usr/bin/env pwsh
# Grimdex publish scrubber — strips operator specifics on the way to the public engine and
# finds anything personal that is left. Fails closed: with no scrub config there is no way
# to know what is personal, so nothing is published. (Spec:
# docs/superpowers/specs/2026-09-28-agents-md-mode-and-publish-hook-design.md, Part A.)
Set-StrictMode -Version Latest

function Get-GrimdexScrubConfig {
    # config/publish-scrub.json: { replacements:[{find,replace,regex?}], deny:[regex], allow:[regex] }
    # Private instance data — never mirrored. Missing or malformed → throw.
    param([Parameter(Mandatory)][string]$GrimdexRoot)
    $path = Join-Path $GrimdexRoot 'config' 'publish-scrub.json'
    if (-not (Test-Path $path)) {
        throw "No scrub config at $path. Copy config/publish-scrub.example.json and list your personal identifiers; publishing is refused without it."
    }
    try { $raw = Get-Content $path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Scrub config is not valid JSON: $path ($($_.Exception.Message))" }
    $get = { param($n) $p = $raw.PSObject.Properties[$n]; if ($p -and $null -ne $p.Value) { , @($p.Value) } else { , @() } }
    [pscustomobject]@{
        replacements = & $get 'replacements'
        deny         = & $get 'deny'
        allow        = & $get 'allow'
    }
}

function Invoke-GrimdexScrub {
    # Applies every replacement in order. Literal finds are case-sensitive; regex finds use
    # .NET syntax. Replacement text is always literal (no $1 expansion).
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)]$Config
    )
    $out = $Text
    foreach ($r in @($Config.replacements)) {
        $isRegex = $r.PSObject.Properties['regex'] -and [bool]$r.regex
        $pattern = if ($isRegex) { [string]$r.find } else { [regex]::Escape([string]$r.find) }
        $replace = [string]$r.replace
        $out = [regex]::Replace($out, $pattern, { param($m) $replace }.GetNewClosure())
    }
    return $out
}

# Built-in shapes of personal data. Each is a regex plus a filter for known-safe matches.
# (A PowerShell escape such as `n directly before an @ is not an email local part.)
$script:GrimdexLeakShapes = @(
    @{ kind = 'email'; pattern = '(?<![\w.+-])(?!(?<=`)[nrt0abfv]@)[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
       safe = '(?i)(noreply|no-reply)@|@(example|users\.noreply\.github)\.(com|org)$|^git@' }
    @{ kind = 'email'; pattern = '(?<![\w.+-])[A-Za-z0-9._+-]+%40[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
       safe = '(?i)(noreply|no-reply)%40|%40example\.(com|org)$' }
    @{ kind = 'home-path'; pattern = '(?i)(/Users/|/home/|[A-Z]:\\{1,2}Users\\{1,2})(?<u>[^/\\\s<>"''`*]+)'  # grimdex:scrub-ok:home-path
       safe = '(?i)(/Users/|/home/|\\Users\\{1,2})(Shared|Public|Default|runner|user|username|yourname|you|me|name|example)\b' }  # grimdex:scrub-ok:home-path
    @{ kind = 'tailnet-ip'; pattern = '\b100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}\b'; safe = $null }
    @{ kind = 'tailnet-ip'; pattern = '(?i)\bfd7a:115c:a1e0:[0-9a-f:]*'; safe = $null }
    @{ kind = 'tailnet-host'; pattern = '(?i)\b[a-z0-9-]+(\.[a-z0-9-]+)*\.ts\.net\b'; safe = '(?i)(^|\.)(example|your-tailnet)\.ts\.net$' }
    @{ kind = 'lan-ip'; pattern = '\b(192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b'; safe = $null }
)

function Find-GrimdexLeaks {
    # Returns one finding per (line, match): deny-list hits (case-insensitive) plus the
    # built-in shapes. A line matching any allow regex is skipped entirely. A line carrying
    # `grimdex:scrub-ok:<kind>[,<kind>...]` excuses only the named built-in shapes on that
    # line (fixtures, the shape regexes themselves); deny-list hits are never excused.
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)]$Config,
        [string]$Path = ''
    )
    $lines = $Text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if (-not $line) { continue }
        $allowed = $false
        foreach ($a in @($Config.allow)) { if ($line -match $a) { $allowed = $true; break } }
        if ($allowed) { continue }
        foreach ($d in @($Config.deny)) {
            foreach ($m in [regex]::Matches($line, [string]$d, 'IgnoreCase')) {
                [pscustomobject]@{ path = $Path; line = $i + 1; kind = 'deny'; match = $m.Value }
            }
        }
        $excused = @()
        $mk = [regex]::Match($line, 'grimdex:scrub-ok:([a-z,-]+)')
        if ($mk.Success) { $excused = $mk.Groups[1].Value -split ',' }
        foreach ($s in $script:GrimdexLeakShapes) {
            if ($s.kind -in $excused) { continue }
            foreach ($m in [regex]::Matches($line, $s.pattern)) {
                if ($s.safe -and $m.Value -match $s.safe) { continue }
                [pscustomobject]@{ path = $Path; line = $i + 1; kind = $s.kind; match = $m.Value }
            }
        }
    }
}

function Test-GrimdexTextBytes {
    # Text unless the first 8 KB hold a NUL byte (the git heuristic) — except UTF-16 with a
    # BOM, which is text full of NULs and must still be scanned.
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    if ($Bytes.Length -ge 2 -and (($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) -or ($Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF))) { return $true }
    $n = [Math]::Min($Bytes.Length, 8192)
    for ($i = 0; $i -lt $n; $i++) { if ($Bytes[$i] -eq 0) { return $false } }
    return $true
}

function ConvertFrom-GrimdexBytes {
    # Decodes by BOM (UTF-8/UTF-16/UTF-32), else UTF-8.
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $ms = [IO.MemoryStream]::new($Bytes)
    $sr = [IO.StreamReader]::new($ms, [Text.UTF8Encoding]::new($false), $true)
    try { $sr.ReadToEnd() } finally { $sr.Dispose() }
}

function Test-GrimdexTextFile {
    param([Parameter(Mandatory)][string]$Path)
    # .NET resolves relative paths against the process cwd, not the pwsh location.
    Test-GrimdexTextBytes -Bytes ([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).ProviderPath))
}
