<#
.SYNOPSIS
    Install, build and start the three halves of ShadowRuler: the game API,
    the chat API and the app.

.DESCRIPTION
    Three steps, in order, and the next is not taken if the last one failed:

      install   dotnet restore for both APIs, npm install for the app
      build     each API published into a folder of its own beside this
                script, and the app type-checked
      start     each in a window of its own, with the commands the project
                is meant to be started with:

        ShadowRuler   dotnet run --project ShadowRuler.API --launch-profile http
        SRMessage     dotnet run --project SRMessage.API
        SR_Front      npx expo start --no-dev --minify --clear

    What the sandbox holds once it has been run:

        server\                 the game API, built
        server\logs\api\        everything the game says but the database
        server\logs\db\         what the database says
        chat\                   the chat API, built
        chat\logs\api\          everything the chat says but the database
        chat\logs\db\           what its database says
        chat\logs\rooms\        a folder a day: the sockets, and each room
        pics\                   every picture a player puts up

    The three folders stand beside each other on purpose: the pictures are
    the one thing in here that is neither service's to own, and a player's
    face outlives any number of rebuilds of either.

    Where those folders are is told to the services as they start, through
    the two settings both of them read: Logs__Path and Pictures__Root. So a
    service started by this script writes here, and the same service started
    by hand writes where it always did.

    A service already listening on its port is left alone and said so. That
    is not only politeness: a running API holds its own exe open, and
    building over it fails with MSB3027 rather than anything that reads like
    the real trouble.

.PARAMETER NoInstall
    Skip the restore and the npm install.

.PARAMETER NoBuild
    Skip the build. Implies -NoInstall.

.PARAMETER Game
.PARAMETER Chat
.PARAMETER App
    Work on only the ones named. All three when none is.

.EXAMPLE
    .\start.ps1
    .\start.ps1 -Game -Chat
    .\start.ps1 -App -NoBuild
#>
[CmdletBinding()]
param(
    [switch]$NoInstall,
    [switch]$NoBuild,
    [switch]$Game,
    [switch]$Chat,
    [switch]$App
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) { $root = "D:\src\SRSandBox" }

# Where everything the running services write ends up. Named once here, handed
# to the services as they start, and made before any of them is.
$serverDir = Join-Path $root "server"
$chatDir   = Join-Path $root "chat"
$picsDir   = Join-Path $root "pics"

# Named once, because four things read each of these: what is installed, what
# is built, what is started, and which port says it is already up.
$services = @(
    [pscustomobject]@{
        Key     = "Game"
        Name    = "ShadowRuler"
        Path    = Join-Path $root "ShadowRuler"
        Install = "dotnet restore ShadowRuler.sln"
        # Published rather than built: a publish is the whole of what the
        # service needs in one folder, which is what "server" is for.
        Build   = "dotnet publish ShadowRuler.API -c Debug -o `"$serverDir`" --nologo -v q"
        Start   = "dotnet run --project ShadowRuler.API --launch-profile http"
        Port    = 5220
        # What the window it runs in is told before it starts.
        Env     = @{
            "Logs__Path"      = (Join-Path $serverDir "logs")
            "Pictures__Root"  = $picsDir
        }
    },
    [pscustomobject]@{
        Key     = "Chat"
        Name    = "SRMessage"
        Path    = Join-Path $root "SRMessage"
        Install = "dotnet restore SRMessage.sln"
        Build   = "dotnet publish SRMessage.API -c Debug -o `"$chatDir`" --nologo -v q"
        Start   = "dotnet run --project SRMessage.API"
        Port    = 50776
        Env     = @{
            "Logs__Path" = (Join-Path $chatDir "logs")
        }
    },
    [pscustomobject]@{
        Key     = "App"
        Name    = "SR_Front"
        Path    = Join-Path $root "SR_Front"
        Install = "npm install"
        # The nearest thing the app has to a compile, and what catches a
        # broken screen before Metro hands it to a phone.
        Build   = "npx tsc --noEmit"
        Start   = "npx expo start --no-dev --minify --clear"
        Port    = 8081
        Env     = @{}
    }
)

# Which were asked for. None named means all of them.
$asked = @()
if ($Game) { $asked += "Game" }
if ($Chat) { $asked += "Chat" }
if ($App)  { $asked += "App" }
if ($asked.Count -eq 0) { $asked = @("Game", "Chat", "App") }
$wanted = $services | Where-Object { $asked -contains $_.Key }

function Test-PortBusy([int]$port) {
    try {
        $held = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
        return ($null -ne $held)
    } catch {
        # No Get-NetTCPConnection on this box: take the port as free rather
        # than refusing to start anything over a missing cmdlet.
        return $false
    }
}

function Invoke-In([string]$path, [string]$command, [string]$shell) {
    Push-Location $path
    try {
        # Out-Host, not a bare call: what the build prints would otherwise be
        # the function's return value, and a restore that said two lines about
        # itself came back as an array of two lines and a nought, which is not
        # a nought and so read as a failure.
        & $shell -NoProfile -Command $command | Out-Host
        return $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

# The window each service runs in. PowerShell 7 where the box has it, Windows
# PowerShell otherwise; both take -NoExit, which is what leaves the log up
# after the service stops.
$shell = "powershell"
if (Get-Command pwsh -ErrorAction SilentlyContinue) { $shell = "pwsh" }

Write-Host ""
Write-Host "ShadowRuler sandbox, at $root" -ForegroundColor Cyan

# ── what is already up ───────────────────────────────────────────────────
$toRun = @()
foreach ($s in $wanted) {
    if (-not (Test-Path $s.Path)) {
        Write-Host ("  {0,-12} no folder at {1}" -f $s.Name, $s.Path) -ForegroundColor Red
        continue
    }
    if (Test-PortBusy $s.Port) {
        Write-Host ("  {0,-12} already up on {1}, left alone" -f $s.Name, $s.Port) -ForegroundColor DarkYellow
        continue
    }
    $toRun += $s
}
if ($toRun.Count -eq 0) {
    Write-Host ""
    Write-Host "Nothing to start." -ForegroundColor Yellow
    return
}

# ── the one file a clone cannot bring with it ────────────────────────────
#
# Secrets.json holds the game's connection string and is kept out of the
# repository, but the Models project copies it as content, so a fresh clone
# does not build without it. Said plainly here, because what MSBuild says
# about it (MSB3030) reads like a broken build rather than a missing secret.
$gameWanted = $toRun | Where-Object { $_.Key -eq "Game" }
if ($gameWanted) {
    $secrets = Join-Path $gameWanted.Path "ShadowRuler.Models\Shared\Secrets.json"
    if (-not (Test-Path $secrets)) {
        Write-Host ""
        Write-Host "  ShadowRuler has no Secrets.json, and will not build without one." -ForegroundColor Red
        Write-Host "  It is one line, and it is kept out of the repository:" -ForegroundColor DarkGray
        Write-Host "      $secrets" -ForegroundColor DarkGray
        Write-Host '      { "ConnectionString": "Host=localhost;Port=5432;Database=game_0;Username=postgres;Password=..." }' -ForegroundColor DarkGray
        Write-Host "  Copy the one from a checkout that has it, or write it out, and run this again." -ForegroundColor DarkGray
        exit 1
    }
}

# ── the folders everything writes into ───────────────────────────────────
foreach ($dir in @($serverDir, $chatDir, $picsDir,
                   (Join-Path $serverDir "logs"), (Join-Path $chatDir "logs"))) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

# ── install ──────────────────────────────────────────────────────────────
if ($NoBuild -or $NoInstall) {
    Write-Host "  (install skipped)" -ForegroundColor DarkGray
} else {
    Write-Host ""
    Write-Host "Installing" -ForegroundColor Cyan
    $failed = @()
    foreach ($s in $toRun) {
        Write-Host ("  {0,-12} {1}" -f $s.Name, $s.Install) -ForegroundColor DarkGray
        if ((Invoke-In $s.Path $s.Install $shell) -ne 0) { $failed += $s.Name }
    }
    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Host ("Install failed: " + ($failed -join ", ") + ". Nothing started.") -ForegroundColor Red
        exit 1
    }
}

# ── build ────────────────────────────────────────────────────────────────
if ($NoBuild) {
    Write-Host "  (build skipped)" -ForegroundColor DarkGray
} else {
    Write-Host ""
    Write-Host "Building" -ForegroundColor Cyan
    $failed = @()
    foreach ($s in $toRun) {
        Write-Host ("  {0,-12} {1}" -f $s.Name, $s.Build) -ForegroundColor DarkGray
        # The build's own output is shown: a compile error is the one thing
        # anybody running this wants to read in full.
        if ((Invoke-In $s.Path $s.Build $shell) -ne 0) { $failed += $s.Name }
    }
    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Host ("Build failed: " + ($failed -join ", ") + ". Nothing started.") -ForegroundColor Red
        exit 1
    }
}

# ── start ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Starting" -ForegroundColor Cyan
foreach ($s in $toRun) {
    $title = "{0} :{1}" -f $s.Name, $s.Port
    # Said to the window before the service in it: the two settings are read
    # at startup, and a service told nothing writes where it always did.
    $sets = ""
    foreach ($key in $s.Env.Keys) {
        $sets += "`$env:$key = '$($s.Env[$key])'; "
    }
    # The title is set inside the window rather than by Start-Process, which
    # has no say over it, so the three are tellable apart on the taskbar.
    $command = "`$host.UI.RawUI.WindowTitle = '$title'; Set-Location '$($s.Path)'; $sets$($s.Start)"
    Start-Process -FilePath $shell -ArgumentList @("-NoExit", "-NoProfile", "-Command", $command) | Out-Null
    Write-Host ("  {0,-12} {1}" -f $s.Name, $s.Start) -ForegroundColor Green
}

Write-Host ""
Write-Host "  Game API   http://localhost:5220/graphql" -ForegroundColor DarkGray
Write-Host "  Chat API   http://localhost:50776" -ForegroundColor DarkGray
Write-Host "  App        http://localhost:8081" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  server\logs\api, server\logs\db, chat\logs\api, chat\logs\db, chat\logs\rooms, pics" -ForegroundColor DarkGray
Write-Host ""
