<#
    cleanup.ps1 - removes the rat2 test implant completely.

    Testing/cleanup tool only, it is not part of the loader. It removes every
    artifact the implant and its loader leave behind: the logon task, the Run
    key, the drop folder, the elevated v20 helper inside the browser dirs,
    the Defender exclusions and the policy bits that switched the scanners
    off, plus the temp traces.

    Usage (elevates itself):
        powershell -NoP -EP Bypass -File cleanup.ps1
        powershell -NoP -EP Bypass -File cleanup.ps1 -DryRun
        powershell -NoP -EP Bypass -File cleanup.ps1 -LeaveDefenderOff
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$LeaveDefenderOff
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($DryRun) {
        Write-Host 'not elevated: re-run from an elevated shell for a complete sweep' -ForegroundColor Yellow
    } else {
        Write-Host 'elevating...' -ForegroundColor Yellow
        $argList = @('-NoP', '-EP', 'Bypass', '-File', "`"$PSCommandPath`"")
        if ($LeaveDefenderOff) { $argList += '-LeaveDefenderOff' }
        try {
            Start-Process powershell -Verb RunAs -ArgumentList $argList
            return
        } catch {
            Write-Host 'elevation refused, continuing half-blind' -ForegroundColor Yellow
        }
    }
}

$taskName   = 'CryptSvcHelper'
$dropDir    = Join-Path $env:LOCALAPPDATA 'Microsoft\CryptoData'
$runKey     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runKeyLM   = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
$codexKey   = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
$defPaths   = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths'
$defProcs   = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes'
$defExts    = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Extensions'
$defPolicy  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
$defRtp     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'

$removed = New-Object System.Collections.Generic.List[string]
function Step($what, [scriptblock]$action) {
    try {
        if ($DryRun) { Write-Host "  would  $what" -ForegroundColor DarkGray; return }
        $action.Invoke()
        Write-Host "  removed $what" -ForegroundColor Green
        $removed.Add($what) | Out-Null
    } catch {
        Write-Host "  skipped $what ($($_.Exception.Message))" -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'rat2 cleanup' -ForegroundColor Cyan
Write-Host "  host   $env:COMPUTERNAME / $env:USERNAME"
Write-Host "  drop   $dropDir"
if ($DryRun) { Write-Host '  mode   DRY RUN, nothing is deleted' -ForegroundColor Yellow }
Write-Host ''

# ------------------------------------------------------------------ process
Write-Host 'processes' -ForegroundColor Cyan
foreach ($name in @('rat', 'ratv20')) {
    $procs = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { Write-Host "  none   $name" -ForegroundColor DarkGray; continue }
    foreach ($p in $procs) {
        Step "$name.exe (pid $($p.Id))" { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    }
}
if (-not $DryRun) {
    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Get-Process -Name rat, ratv20 -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 250
    }
}

# --------------------------------------------------------------------- task
Write-Host 'scheduled tasks' -ForegroundColor Cyan
$taskNames = @($taskName)
# plus anything whose action points at our exe, whatever it is called
# (WinDefUpdate / WindowsUpdateHelper are python jobs and stay untouched)
try {
    foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue) {
        if ($taskNames -contains $t.TaskName) { continue }
        foreach ($a in $t.Actions) {
            if ($a.Execute -and $a.Execute -match 'CryptoData\\rat\.exe|\\rat\.exe$') { $taskNames += $t.TaskName }
            elseif ($a.Arguments -and $a.Arguments -match 'CryptoData\\rat\.exe') { $taskNames += $t.TaskName }
        }
    }
} catch { }

foreach ($t in ($taskNames | Select-Object -Unique)) {
    $exists = $null
    try { $exists = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue } catch { }
    if (-not $exists) { continue }
    Step "task $t" {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop
    }
}

# ----------------------------------------------------------------- registry
Write-Host 'registry' -ForegroundColor Cyan
foreach ($k in @($runKey, $runKeyLM, $codexKey)) {
    if (-not (Test-Path $k)) { continue }
    $names = @()
    try { $names = @((Get-Item $k -ErrorAction Stop).GetValueNames()) }
    catch { Write-Host "  needs elevation: $k" -ForegroundColor Yellow; continue }
    foreach ($v in $names) {
        $data = (Get-ItemProperty -Path $k -Name $v -ErrorAction SilentlyContinue).$v
        if ($v -eq $taskName -or ($data -and $data -match 'CryptoData\\rat\.exe')) {
            Step "$k\$v" { Remove-ItemProperty -Path $k -Name $v -Force -ErrorAction Stop }
        }
    }
}

# ---------------------------------------------------------------- defenders
Write-Host 'defender exclusions' -ForegroundColor Cyan
# the cmdlets first: a running Defender rewrites its registry store from memory,
# so registry-only deletions come back. the registry pass below is the fallback
# for hosts where the service is stopped or a third-party av owns the store.
$mp = $null
try { $mp = Get-MpPreference -ErrorAction Stop } catch { Write-Host '  defender not queryable here' -ForegroundColor Yellow }
if ($mp) {
    foreach ($p in @($mp.ExclusionPath)) {
        if (-not $p) { continue }
        $norm = $p.TrimEnd('\')
        if ($norm -like "$($dropDir.TrimEnd('\'))*" -or $norm -ieq $env:TEMP.TrimEnd('\') -or $norm -match 'rat2\\dist') {
            Step "exclusion $p" { Remove-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue }
        }
    }
    foreach ($p in @($mp.ExclusionProcess)) {
        if ($p -and ($p -ieq 'rat.exe' -or $p -ieq 'probe.exe')) {
            Step "exclusion process $p" { Remove-MpPreference -ExclusionProcess $p -ErrorAction SilentlyContinue }
        }
    }
    foreach ($e in @($mp.ExclusionExtension)) {
        if ($e -ieq '.exe') { Step "exclusion extension $e" { Remove-MpPreference -ExclusionExtension $e -ErrorAction SilentlyContinue } }
    }
}

$knownPaths = @($dropDir, $env:TEMP)
foreach ($k in @($defPaths, $defProcs, $defExts)) {
    if (-not (Test-Path $k)) { continue }
    $names = @()
    try { $names = @((Get-Item $k -ErrorAction Stop).GetValueNames()) }
    catch { Write-Host "  needs elevation: $k" -ForegroundColor Yellow; continue }
    foreach ($v in $names) {
        $ours = $false
        if ($k -eq $defPaths) {
            foreach ($p in $knownPaths) { if ($v -ieq $p -or $v -ilike "$dropDir*") { $ours = $true } }
        } elseif ($k -eq $defProcs) {
            if ($v -ieq 'rat.exe') { $ours = $true }
        } elseif ($k -eq $defExts) {
            if ($v -ieq '.exe') { $ours = $true }
        }
        if ($ours) { Step "exclusion $v" { Remove-ItemProperty -Path $k -Name $v -Force -ErrorAction Stop } }
    }
}

if (-not $LeaveDefenderOff) {
    Write-Host 'defender state' -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host '  would  drop the policy values and re-enable the scanners' -ForegroundColor DarkGray
    } else {
        foreach ($v in @('DisableAntiSpyware')) {
            try {
                if ((Get-ItemProperty -Path $defPolicy -Name $v -ErrorAction SilentlyContinue).$v) {
                    Remove-ItemProperty -Path $defPolicy -Name $v -Force -ErrorAction Stop
                    Write-Host "  reset  policy $v" -ForegroundColor Green
                }
            } catch { Write-Host "  skipped policy $v" -ForegroundColor Yellow }
        }
        foreach ($v in @('DisableRealtimeMonitoring', 'DisableBehaviorMonitoring', 'DisableIOAVProtection')) {
            try {
                if ((Get-ItemProperty -Path $defRtp -Name $v -ErrorAction SilentlyContinue).$v) {
                    Remove-ItemProperty -Path $defRtp -Name $v -Force -ErrorAction Stop
                    Write-Host "  reset  policy $v" -ForegroundColor Green
                }
            } catch { Write-Host "  skipped policy $v" -ForegroundColor Yellow }
        }
        try {
            Set-MpPreference -DisableRealtimeMonitoring $false -EA 0
            Set-MpPreference -DisableIOAVProtection $false -EA 0
            Set-MpPreference -DisableScriptScanning $false -EA 0
            Set-MpPreference -DisableBehaviorMonitoring $false -EA 0
            Write-Host '  reset  realtime scanning on' -ForegroundColor Green
        } catch { Write-Host '  skipped defender preferences' -ForegroundColor Yellow }
        try {
            if (Get-MpComputerStatus -EA 0) { Start-MpScan -ScanType QuickScan -EA 0 }
        } catch { }
    }
}

# -------------------------------------------------------------------- files
Write-Host 'files' -ForegroundColor Cyan
$helperDirs = @(
    "$env:ProgramFiles\Microsoft\Edge\Application",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application",
    "$env:ProgramFiles\Google\Chrome\Application",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application",
    "$env:LOCALAPPDATA\Programs\Google\Chrome\Application",
    "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application",
    "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application",
    "$env:LOCALAPPDATA\Programs\BraveSoftware\Brave-Browser\Application"
)
foreach ($d in $helperDirs) {
    $h = Join-Path $d 'ratv20.exe'
    if (Test-Path $h) { Step "helper $h" { Remove-Item $h -Force -ErrorAction Stop } }
}

if (Test-Path $dropDir) {
    Step "folder $dropDir" { Remove-Item $dropDir -Recurse -Force -ErrorAction Stop }
}

$temp = $env:TEMP
$tempFiles = @('rat2.log', 'rat_task.xml', 'rat_harden.ps1', 'jar.txt', 'rat_gone.exe',
               'dp4.txt', 'v20.bin', 'probe.txt')
foreach ($f in $tempFiles) {
    $p = Join-Path $temp $f
    if (Test-Path $p) { Step "file $p" { Remove-Item $p -Force -ErrorAction Stop } }
}
foreach ($pat in @('dp*.ps1', 'c[1-6].bin', 'rat_*.log')) {
    foreach ($p in @(Get-ChildItem -Path $temp -Filter $pat -File -ErrorAction SilentlyContinue)) {
        Step "file $($p.FullName)" { Remove-Item $p.FullName -Force -ErrorAction Stop }
    }
}
foreach ($p in @(Get-ChildItem -Path $temp -Filter 'ratprof_*' -Directory -ErrorAction SilentlyContinue)) {
    Step "folder $($p.FullName)" { Remove-Item $p.FullName -Recurse -Force -ErrorAction Stop }
}
if (Test-Path 'C:\Users\Public\rn.exe') { Step 'C:\Users\Public\rn.exe' { Remove-Item 'C:\Users\Public\rn.exe' -Force } }
if (Test-Path 'C:\Users\Public\h1.txt') { Step 'C:\Users\Public\h1.txt' { Remove-Item 'C:\Users\Public\h1.txt' -Force } }

# ------------------------------------------------------------------- verify
Write-Host ''
Write-Host 'leftovers' -ForegroundColor Cyan
$left = 0
if (Get-Process -Name rat, ratv20 -ErrorAction SilentlyContinue) { Write-Host '  process rat.exe still running' -ForegroundColor Red; $left++ }
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { Write-Host "  task $taskName still registered" -ForegroundColor Red; $left++ }
if (Test-Path $dropDir) { Write-Host "  folder still there: $dropDir" -ForegroundColor Red; $left++ }
foreach ($k in @($runKey, $runKeyLM)) {
    if ((Get-ItemProperty -Path $k -Name $taskName -ErrorAction SilentlyContinue).$taskName) { Write-Host "  Run value in $k" -ForegroundColor Red; $left++ }
}
if ($left -eq 0) { Write-Host '  clean' -ForegroundColor Green } else { Write-Host "  $left leftover(s)" -ForegroundColor Red }

Write-Host ''
if (-not $DryRun) {
    Write-Host ("done, {0} artifact(s) removed" -f $removed.Count) -ForegroundColor Cyan
}
