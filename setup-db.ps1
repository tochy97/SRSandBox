<#
.SYNOPSIS
    Build the three databases from scratch: the accounts directory, the world,
    and the world's chat.

.DESCRIPTION
    Runs, in this order and each against its own database:

        DBScripts\game\main.sql            -> the accounts directory  (main)
        DBScripts\game\game.sql            -> the world               (game_0)
        DBScripts\game\GenerateServer.sql  -> the world's map, onto it (game_0)
        DBScripts\chat\chat.sql            -> the world's chat        (chat_0)

    Where each goes, and how to sign in to it, is read from the two APIs' own
    settings rather than written down a second time here:

        ShadowRuler\ShadowRuler.API\appsettings.json   Servers:Accounts, and
                                                       Servers:Worlds[Default]
        SRMessage\SRMessage.API\appsettings.json       ConnectionStrings:DefaultConnection

    so the script builds exactly the databases the services will open.

    EVERY ONE OF THESE DROPS AND REBUILDS ITS TABLES. Every account, every
    player, every base and every message in those databases is gone afterwards.
    The script says which databases it is about to empty and waits for "yes",
    unless -Force is given.

    A database that does not exist yet is created first. GenerateServer.sql only
    ever runs straight after game.sql: it lays the map onto an empty world, and
    onto one already played it would lay a second map over the first.

    Stop the APIs first. A service left running holds connections to these
    databases, and its idea of what is in them is wrong the moment this ends.

.PARAMETER Only
    Build only the ones named: main, game, chat. All three when left out.
    Mind that the accounts in main name a player in game: rebuilding one and
    not the other leaves accounts with no player, or players with no account.

.PARAMETER SkipGenerate
    Build the world's tables but leave its map empty.

.PARAMETER Force
    Do not ask before emptying the databases.

.EXAMPLE
    .\setup-db.ps1
    .\setup-db.ps1 -Only chat
    .\setup-db.ps1 -Only game -SkipGenerate -Force
#>
[CmdletBinding()]
param(
    [ValidateSet("main", "game", "chat")]
    [string[]]$Only,
    [switch]$SkipGenerate,
    [switch]$Force
)

# Not Stop: psql writes its notices to stderr, and under Stop PowerShell 5.1
# turns the first of them into a terminating error. Each run is judged by its
# exit code instead see Invoke-Psql.
$ErrorActionPreference = "Continue"
$root = $PSScriptRoot
if (-not $root) { $root = "D:\src\SRSandBox" }

# ── where everything is ───────────────────────────────────────────────────

$scripts = Join-Path $root "DBScripts"
$gameSettings = Join-Path $root "ShadowRuler\ShadowRuler.API\appsettings.json"
$chatSettings = Join-Path $root "SRMessage\SRMessage.API\appsettings.json"

function Fail($message) {
    Write-Host ""
    Write-Host $message -ForegroundColor Red
    exit 1
}

foreach ($file in @($gameSettings, $chatSettings)) {
    if (-not (Test-Path $file)) { Fail "Cannot find $file, which says where the databases are." }
}

# "Host=localhost;Port=5432;Database=main;Username=postgres;Password=..." as a
# table, keys in any case.
function Read-ConnectionString([string]$text) {
    $parts = @{}
    foreach ($pair in $text.Split(";")) {
        $at = $pair.IndexOf("=")
        if ($at -lt 1) { continue }
        $parts[$pair.Substring(0, $at).Trim().ToLowerInvariant()] = $pair.Substring($at + 1).Trim()
    }
    return $parts
}

function Get-Target([string]$name, [string]$text) {
    $c = Read-ConnectionString $text
    if (-not $c["database"]) { Fail "The $name connection string names no database." }
    return [pscustomobject]@{
        Name     = $name
        Host     = if ($c["host"]) { $c["host"] } else { "localhost" }
        Port     = if ($c["port"]) { $c["port"] } else { "5432" }
        User     = if ($c["username"]) { $c["username"] } elseif ($c["user id"]) { $c["user id"] } else { "postgres" }
        Password = $c["password"]
        Database = $c["database"]
    }
}

$game = Get-Content $gameSettings -Raw | ConvertFrom-Json
$chat = Get-Content $chatSettings -Raw | ConvertFrom-Json
$worldName = $game.Servers.Default
$worldConnection = $game.Servers.Worlds.$worldName
if (-not $worldConnection) { Fail "Servers:Worlds has no world named '$worldName', which Servers:Default names." }

$targets = [ordered]@{
    main = [pscustomobject]@{
        Target = Get-Target "accounts" $game.Servers.Accounts
        Files  = @(Join-Path $scripts "game\main.sql")
    }
    game = [pscustomobject]@{
        Target = Get-Target "world" $worldConnection
        Files  = @(Join-Path $scripts "game\game.sql") +
                 $(if ($SkipGenerate) { @() } else { @(Join-Path $scripts "game\GenerateServer.sql") })
    }
    chat = [pscustomobject]@{
        Target = Get-Target "chat" $chat.ConnectionStrings.DefaultConnection
        Files  = @(Join-Path $scripts "chat\chat.sql")
    }
}

$chosen = if ($Only) { $Only } else { @("main", "game", "chat") }

foreach ($key in $chosen) {
    foreach ($file in $targets[$key].Files) {
        if (-not (Test-Path $file)) { Fail "Cannot find $file." }
    }
}

# ── psql ──────────────────────────────────────────────────────────────────

# On the path if it is there; otherwise the newest PostgreSQL install's.
$psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
if (-not $psql) {
    $psql = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
        Sort-Object { [int]($_.Directory.Parent.Name -replace "\D", "") } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $psql) { Fail "Cannot find psql. Install PostgreSQL's command-line tools, or put psql on the PATH." }

# Run psql against one database, its password handed over the environment
# rather than the command line, its notices kept to warnings and worse (the
# scripts DROP ... IF EXISTS everything, and every one of those says so).
# Returns the exit code.
function Invoke-Psql($target, [string]$database, [string[]]$arguments) {
    $hadPassword = $env:PGPASSWORD
    $hadOptions = $env:PGOPTIONS
    try {
        if ($target.Password) { $env:PGPASSWORD = $target.Password }
        $env:PGOPTIONS = "--client-min-messages=warning"
        & $psql -h $target.Host -p $target.Port -U $target.User -d $database -v ON_ERROR_STOP=1 -X -q @arguments 2>&1 | Out-Host
        return $LASTEXITCODE
    } finally {
        $env:PGPASSWORD = $hadPassword
        $env:PGOPTIONS = $hadOptions
    }
}

# Whether a database is there, asked of the server's own maintenance one.
function Test-Database($target) {
    $hadPassword = $env:PGPASSWORD
    try {
        if ($target.Password) { $env:PGPASSWORD = $target.Password }
        $name = $target.Database.Replace("'", "''")
        $found = & $psql -h $target.Host -p $target.Port -U $target.User -d postgres -X -t -A `
            -c "SELECT 1 FROM pg_database WHERE datname = '$name'" 2>$null
        if ($LASTEXITCODE -ne 0) { Fail "Cannot reach PostgreSQL at $($target.Host):$($target.Port) as $($target.User)." }
        return ($found -match "1")
    } finally {
        $env:PGPASSWORD = $hadPassword
    }
}

# ── ask first ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "About to build from scratch:" -ForegroundColor Cyan
foreach ($key in $chosen) {
    $t = $targets[$key].Target
    $files = ($targets[$key].Files | ForEach-Object { Split-Path $_ -Leaf }) -join ", "
    Write-Host ("  {0,-9} {1}@{2}:{3}  <- {4}" -f $t.Name, $t.Database, $t.Host, $t.Port, $files)
}
Write-Host ""
Write-Host "Every table in those databases is dropped and built again. Everything in them is lost." -ForegroundColor Yellow
if (-not $Force) {
    $answer = Read-Host "Type yes to go on"
    if ($answer -ne "yes") {
        Write-Host "Nothing was changed."
        exit 0
    }
}

# ── build ─────────────────────────────────────────────────────────────────

foreach ($key in $chosen) {
    $t = $targets[$key].Target
    Write-Host ""
    Write-Host ("{0}: {1}" -f $t.Name, $t.Database) -ForegroundColor Cyan

    if (-not (Test-Database $t)) {
        # An identifier, not a value: quoted by hand, and it comes from the
        # settings file rather than from anybody typing it.
        $quoted = '"' + $t.Database.Replace('"', '""') + '"'
        if ((Invoke-Psql $t "postgres" @("-c", "CREATE DATABASE $quoted")) -ne 0) {
            Fail "Could not create $($t.Database)."
        }
        Write-Host "  created $($t.Database)" -ForegroundColor DarkGray
    }

    foreach ($file in $targets[$key].Files) {
        $leaf = Split-Path $file -Leaf
        Write-Host "  running $leaf" -ForegroundColor DarkGray
        if ((Invoke-Psql $t $t.Database @("-f", $file)) -ne 0) {
            Fail "$leaf failed against $($t.Database). Anything after it was not run."
        }
    }
    Write-Host "  done" -ForegroundColor Green
}

Write-Host ""
Write-Host "All built. Start the services again with .\start.ps1." -ForegroundColor Green
