Add-Type -AssemblyName System.Web

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

$AzureContext

Get-AzSubscription

$appId = Get-AutomationVariable -Name 'LogAnalyticsIngestionAppId'
$appSecret = Get-AutomationVariable -Name 'LogAnalyticsIngestionAppSecret'
$dceEndpoint = Get-AutomationVariable -Name 'dceEndpoint'
$dcrImmutableId = Get-AutomationVariable -Name 'dcrImmutableId'
$TenantId = Get-AutomationVariable -Name 'TenantId'

# Specify the name of the record type that you'll be creating
$LogType = "VmTagsMonitoring"
$streamName = "Custom-$($LogType)_CL"

$VirtualMachineTagInformation = Search-AzGraph -Query 'resources
| where type == "microsoft.compute/virtualmachines" or type == "microsoft.hybridcompute/machines"
| project id, name, location, resourceGroup, subscriptionId, ["tags"]
| extend Locatie = tags["Locatie"], Functie = tags["Functie"]
| project-away ["tags"]'

$VirtualMachineTagInformation

$scope= [System.Web.HttpUtility]::UrlEncode("https://monitor.azure.com//.default")   
$body = "client_id=$appId&scope=$scope&client_secret=$appSecret&grant_type=client_credentials";
$headers = @{"Content-Type"="application/x-www-form-urlencoded"};
$uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$bearerToken = (Invoke-RestMethod -Uri $uri -Method "Post" -Body $body -Headers $headers).access_token

foreach ($VMinfo in $VirtualMachineTagInformation) {
    
$currentTime = Get-Date ([datetime]::UtcNow) -Format O
$staticData = @"
    [
        {  
            "TimeGenerated": "$currentTime",
            "Functie": "$($VMinfo.Functie)",
            "Locatie": "$($VMinfo.Locatie)",
            "resourceGroup": "$($VMinfo.resourceGroup)",
            "subscriptionId": "$($VMinfo.subscriptionId)",
            "resourceId": "$($VMinfo.resourceId)",
            "location": "$($VMinfo.location)"
        }
    ]
"@;

$staticData 


$body = $staticData;
$headers = @{"Authorization"="Bearer $bearerToken";"Content-Type"="application/json"};
$uri = "$dceEndpoint/dataCollectionRules/$dcrImmutableId/streams/$($streamName)?api-version=2021-11-01-preview"

$headers
$uri

Invoke-RestMethod -Uri $uri -Method "Post" -Body $body -Headers $headers

}
