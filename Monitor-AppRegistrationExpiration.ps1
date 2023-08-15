Add-Type -AssemblyName System.Web

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
#AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

Get-AzSubscription

$appId = Get-AutomationVariable -Name 'LogAnalyticsIngestionAppId'
$appSecret = Get-AutomationVariable -Name 'LogAnalyticsIngestionAppSecret'
$dceEndpoint = Get-AutomationVariable -Name 'dceEndpoint'
$dcrImmutableId = Get-AutomationVariable -Name 'dcrImmutableId'
$TenantId = Get-AutomationVariable -Name 'TenantId'

# Specify the name of the record type that you'll be creating
$LogType = "AppRegistrationMonitoring"
$streamName = "Custom-$($LogType)_CL"

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

$scope= [System.Web.HttpUtility]::UrlEncode("https://monitor.azure.com//.default")   
$body = "client_id=$appId&scope=$scope&client_secret=$appSecret&grant_type=client_credentials";
$headers = @{"Content-Type"="application/x-www-form-urlencoded"};
$uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$bearerToken = (Invoke-RestMethod -Uri $uri -Method "Post" -Body $body -Headers $headers).access_token
    
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

$currentTime = Get-Date ([datetime]::UtcNow) -Format O
$staticData = @"
[
    {  
        "TimeGenerated": "$currentTime",
        "Name": "$($AppJson.DisplayName)",
        "ObjectId": "$($AppJson.Id)",
        "AppId": "$($AppJson.AppId)",
        "StartDateTime": "$($cred.StartDateTime)",
        "EndDateTime": "$($cred.EndDateTime)",
        "KeyID": "$($cred.KeyId)",
        "Owner": "$($OwnerName)",
        "Status": "$($Status)"
    }
]
"@;

$staticData

$body = $staticData;
$headers = @{"Authorization"="Bearer $bearerToken";"Content-Type"="application/json"};
$uri = "$dceEndpoint/dataCollectionRules/$dcrImmutableId/streams/$($streamName)?api-version=2021-11-01-preview"

Invoke-RestMethod -Uri $uri -Method "Post" -Body $body -Headers $headers


}

#$AllCredinfo += $credinfo



}
