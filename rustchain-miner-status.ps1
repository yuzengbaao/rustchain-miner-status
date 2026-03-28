<#
.SYNOPSIS
    RustChain Miner Status Check Script (PowerShell)

.DESCRIPTION
    Queries the RustChain Agent Economy node to display miner health
    status and active miner list with formatted, color-coded output.

.NOTES
    Equivalent to:
        curl -s https://50.28.86.131/health | jq .
        curl -s https://50.28.86.131/api/miners | jq '.[] | {...}'

.EXAMPLE
    .\rustchain-miner-status.ps1
    .\rustchain-miner-status.ps1 -Watch
    .\rustchain-miner-status.ps1 -ServerUrl "https://my-node.rustchain.io"
#>

param(
    [string]$ServerUrl = "https://50.28.86.131",
    [switch]$Watch
)

# --- Constants ---
$StaleThresholdMinutes = 10
$WatchIntervalSeconds = 30

# --- Helper Functions ---

function Write-ColorOutput {
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
}

function Get-RustChainHealth {
    <#
    .SYNOPSIS
        Query the /health endpoint and return parsed data.
    #>
    try {
        $response = Invoke-RestMethod -Uri "$ServerUrl/health" -TimeoutSec 15 -SkipCertificateCheck
        return @{
            Success  = $true
            Data     = $response
            ErrorMsg = $null
        }
    }
    catch [System.Net.WebException] {
        $statusCode = $_.Exception.Response.StatusCode.value__
        return @{
            Success  = $false
            Data     = $null
            ErrorMsg = "HTTP $statusCode - $($_.Exception.Message)"
        }
    }
    catch {
        return @{
            Success  = $false
            Data     = $null
            ErrorMsg = $_.Exception.Message
        }
    }
}

function Get-RustChainMiners {
    <#
    .SYNOPSIS
        Query the /api/miners endpoint and return parsed miner list.
    #>
    try {
        $response = Invoke-RestMethod -Uri "$ServerUrl/api/miners" -TimeoutSec 15 -SkipCertificateCheck
        return @{
            Success = $true
            Data    = $response
            ErrorMsg = $null
        }
    }
    catch [System.Net.WebException] {
        $statusCode = $_.Exception.Response.StatusCode.value__
        return @{
            Success  = $false
            Data     = $null
            ErrorMsg = "HTTP $statusCode - $($_.Exception.Message)"
        }
    }
    catch {
        return @{
            Success  = $false
            Data     = $null
            ErrorMsg = $_.Exception.Message
        }
    }
}

function Format-Uptime {
    param([double]$Seconds)
    if ($Seconds -ge 86400) {
        $days = [math]::Floor($Seconds / 86400)
        $hrs  = [math]::Floor(($Seconds % 86400) / 3600)
        return "{0}d {1}h" -f $days, $hrs
    }
    elseif ($Seconds -ge 3600) {
        $hrs  = [math]::Floor($Seconds / 3600)
        $mins = [math]::Floor(($Seconds % 3600) / 60)
        return "{0}h {1}m" -f $hrs, $mins
    }
    else {
        $mins = [math]::Floor($Seconds / 60)
        return "{0}m" -f $mins
    }
}

function Get-TimeAgo {
    param([long]$UnixTimestamp)
    $epoch = [DateTimeOffset]::new(1970, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    $dt = $epoch.AddSeconds($UnixTimestamp)
    $ago = [DateTimeOffset]::UtcNow - $dt
    if ($ago.TotalMinutes -lt 1) {
        return "{0:N0}s ago" -f $ago.TotalSeconds
    }
    elseif ($ago.TotalHours -lt 1) {
        return "{0:N0}m ago" -f $ago.TotalMinutes
    }
    elseif ($ago.TotalDays -lt 1) {
        return "{0:N1}h ago" -f $ago.TotalHours
    }
    else {
        return "{0:N1}d ago" -f $ago.TotalDays
    }
}

function Show-Status {
    <#
    .SYNOPSIS
        Fetch and display full status dashboard.
    #>
    Clear-Host

    # Header
    Write-ColorOutput "========================================" "Cyan"
    Write-ColorOutput "  RustChain Miner Status Dashboard" "Cyan"
    Write-ColorOutput "  Node: $ServerUrl" "DarkGray"
    Write-ColorOutput "  Checked: $([DateTimeOffset]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) UTC" "DarkGray"
    Write-ColorOutput "========================================" "Cyan"
    Write-Host ""

    # --- Health Check ---
    Write-ColorOutput "[Health Check]" "Yellow"
    $health = Get-RustChainHealth

    if ($health.Success) {
        $h = $health.Data

        $statusColor = if ($h.ok -eq $true) { "Green" } else { "Red" }
        $statusLabel = if ($h.ok -eq $true) { "ONLINE" } else { "DEGRADED" }
        Write-ColorOutput "  Status:   $statusLabel" $statusColor

        if ($h.version) {
            Write-Host "  Version:  $($h.version)"
        }
        if ($h.uptime_s) {
            Write-Host "  Uptime:   $(Format-Uptime $h.uptime_s)"
        }
        if ($h.db_rw -ne $null) {
            $dbColor = if ($h.db_rw -eq $true) { "Green" } else { "Red" }
            $dbLabel = if ($h.db_rw -eq $true) { "Read/Write" } else { "Read-Only" }
            Write-ColorOutput "  Database: $dbLabel" $dbColor
        }
        if ($h.backup_age_hours -ne $null) {
            Write-Host ("  Backup:   {0:F2}h ago" -f $h.backup_age_hours)
        }
        if ($h.tip_age_slots -ne $null) {
            Write-Host "  Tip Age:  $($h.tip_age_slots) slots"
        }
    }
    else {
        Write-ColorOutput "  ERROR: $($health.ErrorMsg)" "Red"
        Write-ColorOutput "  Node is offline or unreachable." "Red"
    }

    Write-Host ""

    # --- Miner List ---
    Write-ColorOutput "[Active Miners]" "Yellow"
    $miners = Get-RustChainMiners

    if (-not $miners.Success) {
        Write-ColorOutput "  ERROR: $($miners.ErrorMsg)" "Red"
        Write-ColorOutput "  Cannot retrieve miner list." "Red"
        return
    }

    $minerList = $miners.Data
    if ($null -eq $minerList -or $minerList.Count -eq 0) {
        Write-ColorOutput "  No miners found." "DarkYellow"
        return
    }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # Build table rows
    $tableData = foreach ($m in $minerList) {
        $lastSeenUnix = $m.last_attest
        $minutesSince = if ($lastSeenUnix) {
            [math]::Round(($now - $lastSeenUnix) / 60, 1)
        } else {
            [double]::PositiveInfinity
        }

        $isOnline = $minutesSince -le $StaleThresholdMinutes

        [PSCustomObject]@{
            Status      = if ($isOnline) { "Online" } else { "Stale" }
            Miner       = $m.miner
            Device      = $m.device_family
            Arch        = $m.device_arch
            HW          = $m.hardware_type
            Multiplier  = $m.antiquity_multiplier
            LastSeen    = if ($lastSeenUnix) { Get-TimeAgo $lastSeenUnix } else { "Never" }
            MinutesAgo  = $minutesSince
        }
    }

    # Sort: online first, then by recency
    $tableData = $tableData | Sort-Object { $_.MinutesAgo -eq [double]::PositiveInfinity }, MinutesAgo

    # Display table with color
    $onlineCount = ($tableData | Where-Object { $_.Status -eq "Online" }).Count
    $staleCount  = ($tableData | Where-Object { $_.Status -eq "Stale" }).Count

    Write-Host ""
    Write-ColorOutput "  Online: $onlineCount  |  Stale (>${StaleThresholdMinutes}m): $staleCount  |  Total: $($tableData.Count)" "White"
    Write-Host ""

    foreach ($row in $tableData) {
        $color = if ($row.Status -eq "Online") { "Green" } else { "Red" }
        $statusPad = $row.Status.PadRight(7)
        $minerPad  = if ($row.Miner.Length -gt 30) { $row.Miner.Substring(0, 30) } else { $row.Miner.PadRight(30) }
        $devicePad = if ($row.Device.Length -gt 10) { $row.Device.Substring(0, 10) } else { $row.Device.PadRight(10) }
        $hwPad     = if ($row.HW.Length -gt 24) { $row.HW.Substring(0, 24) } else { $row.HW.PadRight(24) }
        $lastPad   = $row.LastSeen.PadRight(10)
        $multiStr  = ("{0:N2}" -f $row.Multiplier).PadLeft(5)

        Write-ColorOutput "  [$statusPad] $minerPad  $devicePad  $hwPad  x$multiStr  $lastPad" $color
    }

    Write-Host ""
    Write-ColorOutput "========================================" "DarkGray"
    Write-ColorOutput "  Stale threshold: $StaleThresholdMinutes minutes" "DarkGray"
    if ($Watch) {
        Write-ColorOutput "  Auto-refresh: every $WatchIntervalSeconds seconds (Ctrl+C to stop)" "DarkGray"
    }
    Write-ColorOutput "========================================" "DarkGray"
}

# --- Main ---

# Verify PowerShell version (5.1+ required for Windows 10/11)
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.1 or later is required. Current: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    exit 1
}

if ($Watch) {
    Write-Host "Watch mode enabled. Press Ctrl+C to stop." -ForegroundColor DarkYellow
    while ($true) {
        Show-Status
        Start-Sleep -Seconds $WatchIntervalSeconds
    }
}
else {
    Show-Status
}
