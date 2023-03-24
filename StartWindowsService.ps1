param(
    [string]$serviceName
)

# Start the service
Start-Service $serviceName

# Wait for the service to start
$timeout = New-TimeSpan -Minutes 10
$sw = [Diagnostics.Stopwatch]::StartNew()

while ((Get-Service $serviceName).Status -ne "Running") {
    # Check if the timeout has been exceeded
    if ($sw.Elapsed -ge $timeout) {
        Write-Error "Error: The $serviceName service failed to start within 10 minutes."
        exit 1
    }

    # Wait for 1 second before checking the status again
    Start-Sleep -Seconds 1
}

Write-Host "The $serviceName service has started successfully."
