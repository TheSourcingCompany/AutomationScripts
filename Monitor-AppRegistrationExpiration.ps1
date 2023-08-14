# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
#$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

Get-AzSubscription

Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}


# Create the function to create and post the request
Function Post-LogAnalyticsData($customerId, $sharedKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode

}
$CustomerId = Get-AutomationVariable -Name 'WorkspaceID'
$SharedKey = Get-AutomationVariable -Name 'WorkspaceKey'
# Specify the name of the record type that you'll be creating
$LogType = "AppRegistrationMonitoring"

$TimeStampField = Get-Date

$graphToken = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com/"
$aadToken = Get-AzAccessToken -ResourceUrl "https://graph.windows.net"
Connect-AzureAD -AccountId $azureContext.account.id -TenantId $azureContext.tenant.id -AadAccessToken $aadToken.token -MsAccessToken $graphToken.token

$Applications = Get-AzureADMSApplication

$AllCredinfo = @()

foreach ($AppJson in $Applications){

    $owner = $null
    $OwnerName = $null

    $owner = Get-AzureADMSApplicationOwner -ObjectId $AppJson.id
    #Write-Host $owner

    if ($owner.OdataType -ieq "#microsoft.graph.servicePrincipal"){


        $OwnerName = (Get-AzADServicePrincipal -ObjectId $owner.Id).DisplayName

    }
    if ($owner.OdataType -ieq "#microsoft.graph.user"){


        $OwnerName = $(Get-AzADUser -ObjectId $owner.Id).displayname

    }

    $AllCreds = @()

    if ($AppJson.KeyCredentials) {$allcreds += $AppJson.KeyCredentials}

    if ($AppJson.PasswordCredentials) {$allcreds += $AppJson.PasswordCredentials}


$credinfo = @()
    
foreach ($cred in $allcreds){


if ($cred.EndDateTime -lt $(get-date).AddDays(30) -and $cred.EndDateTime -gt $(Get-Date)){Write-Host ("App: {0} Credential with ID {1} will expire within 30 days: {2}" -f $AppJson.DisplayName, $cred.KeyId, $cred.EndDateTime); $Status = "Expiring"}
if ($cred.EndDateTime -lt $(get-date)){Write-Host ("App: {0} Credential with ID {1} expired: {2}" -f $AppJson.DisplayName, $cred.KeyId, $cred.EndDateTime); $Status = "Expired"}
if ($cred.EndDateTime -gt $(get-date).AddDays(30)){Write-Host ("App: {0} Credential with ID {1} is valid: {2}" -f $AppJson.DisplayName, $cred.KeyId, $cred.EndDateTime); $Status = "Valid"}

$credinfo += [PSCustomObject] @{
    Name = $AppJson.DisplayName
    ObjectId = $AppJson.Id
    AppId = $AppJson.AppId
    StartDateTime = $cred.StartDateTime
    EndDateTime = $cred.EndDateTime
    KeyID = $cred.KeyId
    Owner = $OwnerName
    Status = $Status

}

$json = @"
{  
    "Name": "$($AppJson.DisplayName)",
    "ObjectId": "$($AppJson.Id)",
    "AppId": "$($AppJson.AppId)",
    "StartDateTime": "$($cred.StartDateTime)",
    "EndDateTime": "$($cred.EndDateTime)",
    "KeyID": "$($cred.KeyId)",
    "Owner": "$($OwnerName)",
    "Status": "$($Status)"
}
"@

$json

Post-LogAnalyticsData -customerId $customerId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($json)) -logType $logType



}

#$AllCredinfo += $credinfo



}
