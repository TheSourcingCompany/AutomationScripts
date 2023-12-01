$ADSyncStatus = (Get-ADSyncScheduler).SyncCycleInProgress
While ($ADSyncStatus -eq $True) { # True equals running cycle, False equals no running cycle
    $date = (get-date -format "g")
    Write-Host "$date Sync cycle is busy, waiting 30 seconds and checking again..."
    Start-Sleep -Seconds 30
    Try {
        $ADSyncStatus = (Get-ADSyncScheduler).SyncCycleInProgress
    }
    Catch {
        # Log the error
        $ErrorMessage = $_.Exception.Message
        $ErrorTime = Get-Date -Format "g"
        Write-Host "An error occurred at $ErrorTime $ErrorMessage"

    }
}

# Start a new sync cycle if not already running
If ($ADSyncStatus -eq $False) {
    Try {
        Start-ADSyncSyncCycle -PolicyType Delta
        Write-Host "ADSync sync cycle started."
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        Write-Host "Failed to start ADSync sync cycle: $ErrorMessage"
    }
}