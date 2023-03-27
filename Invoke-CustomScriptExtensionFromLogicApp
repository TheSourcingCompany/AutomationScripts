<#
    .DESCRIPTION
        Invoke custom script extension

    .NOTES
        AUTHOR: Anthony Kersten en Roeland van den Bosch
        COMPANY: The Sourcing Company
        LASTEDIT: 2022-02-17
#>

# PSEdition options: Core (PowerShell Core), Desktop (Windows PowerShell)
#Requires -PSEdition Desktop

# Define required installed modules
#Requires -Modules Az.Accounts, Az.Storage, Az.ConnectedMachine

##################################################################
# Parameter(s)
##################################################################
#region Parameter(s)

[CmdletBinding(SupportsShouldProcess)]
param
(
    [Parameter()]
    [object]$WebHookData
)

#endregion Parameter(s)
##################################################################

##################################################################
# Variable(s)
##################################################################
#region Variable(s)

# Setting InfomationPreference to continue script execution when warning occurs
$InformationPreference = 'Continue'
# Setting WarningPreference to continue script execution when warning occurs
# $WarningPreference = 'Continue'
# Setting ErrorActionPreference to Continue script execution when error occurs
# $ErrorActionPreference = 'Continue'

[string]$RunbookName = 'Invoke-CustomScriptExtension'
[string[]]$RequiredModules = @('Az.Accounts','Az.Storage','Az.ConnectedMachine')
[string[]]$MandatoryRequestBodyVariables = @('ScriptFileName','VMResourceGroupName','VMName')

[boolean]$RunAsRunbook = $false
if ($PSPrivateMetadata.JobId) {
    $RunAsRunbook = $true
}

if (!$RunAsRunbook) {
    Clear-Host
}

#endregion Variable(s)
##################################################################

##################################################################
# Class(es)
##################################################################
#region Class(es)

class WebHookDataRequestBody {
    [guid]$SubscriptionID = '8051b575-7058-426e-889e-9c585eb358b4'
    [guid]$StorageAccountSubscriptionId = '8051b575-7058-426e-889e-9c585eb358b4'
    [string]$StorageAccountResourceGroupName = 'tsccloud-mgmt-services'
    [string]$StorageAccountName = 'tsccustomscripts'
    [string]$StorageContainerName = 'customscripts'
    [string]$ScriptFolderName = 'upload'
    [string]$ScriptFileName
    [string]$ScriptBlock
    [string]$ScriptInputFile
    [string]$VMResourceGroupName
    [string]$VMName
    [boolean]$ArcMachine = $false
    [boolean]$Debug = $false
}

#endregion Class(es)
##################################################################

##################################################################
# Default Function(s)
##################################################################
#region Default function(s)

function Stop-Script {
    <#
        .SYNOPSIS
        This function is used to stop a script in a clean way
        .DESCRIPTION
        The function writes a warning and exits the script
        .EXAMPLE
        Stop-Script
        .NOTES
        NAME: Stop-Script
    #>
    param()
    BEGIN {
        Write-Debug -Message "Start function:`t`t`t[Stop-Script]"
    }
    PROCESS {
        Write-Warning -Message 'Script has been stopped by an error'
        Exit
    }
    END {
        Write-Debug -Message "End function:`t`t`t`t[Get-BaselineVersion]"
    }
}

#endregion Default function(s)
##################################################################

##################################################################
# Import module(s)
##################################################################
#region Import module(s)

Write-Output ('-' * 75)
Write-Output " * Import module(s)"

foreach ($RequiredModule in $RequiredModules) {
    Write-Output ("   + Import standard module [{0}]" -f $RequiredModule)
    Import-Module -Name $RequiredModule -Force -ErrorAction Stop
}

Write-Output ('-' * 75)

#endregion Import module(s)
##################################################################

##################################################################
# Main
##################################################################
#region Main

Write-Output ('-' * 75)
Write-Output (" * Start [{0}]" -f $RunbookName)

# Check for input data
if ($WebHookData)
{
    if ($WebHookData.GetType().Name -ieq 'String') {
        try {
            $WebHookData = $WebHookData | ConvertFrom-Json
        }
        catch {
            Write-Error ("Invalid WebHookData: [{0}]" -f $WebHookData.ToString())
            Stop-Script
        }
    }

    if ($WebHookData.PSObject.Properties.Name -contains 'RequestBody') {
        if ($WebHookData.RequestBody.GetType().Name  -ieq 'String') {
            try {
                # [WebHookDataRequestBody]$RequestBody = $WebHookData.RequestBody | ConvertFrom-Json
                [WebHookDataRequestBody]$RequestBody = [System.Web.Script.Serialization.JavaScriptSerializer]::new().Deserialize(($WebHookData.RequestBody), [WebHookDataRequestBody])
            }
            catch {
                Write-Error ("Invalid WebHookData RequestBody: [{0}]" -f $WebHookData.RequestBody.ToString())
                Stop-Script
            }
        }
        else {
            [WebHookDataRequestBody]$RequestBody = $WebHookData.RequestBody
        }

        #region Check for mandatory RequestBody variable
        foreach ($MandatoryRequestBodyVariable in $MandatoryRequestBodyVariables) {
            if (!($RequestBody."$MandatoryRequestBodyVariable")) {
                Write-Warning -Message ("Missing RequestBody variable [{0}]!" -f $MandatoryRequestBodyVariable)
                Stop-Script
            }
        }
        #endregion Check for mandatory variable

        #region Show variable information
        Write-Output ("   {0}" -f ('#' * 72))
        Write-Output ("   # SubscriptionId:`t`t`t[{0}]" -f $RequestBody.SubscriptionId)
        Write-Output ("   # StorageAccountSubscriptionId:`t[{0}]" -f $RequestBody.StorageAccountSubscriptionId)
        Write-Output ("   # StorageAccountResourceGroupName:`t[{0}]" -f $RequestBody.StorageAccountResourceGroupName)
        Write-Output ("   # StorageAccountName:`t`t[{0}]" -f $RequestBody.StorageAccountName)
        Write-Output ("   # StorageContainerName:`t`t[{0}]" -f $RequestBody.StorageContainerName)
        Write-Output ("   # ScriptFolderName:`t`t`t[{0}]" -f $RequestBody.ScriptFolderName)
        Write-Output ("   # ScriptFileName:`t`t`t[{0}]" -f $RequestBody.ScriptFileName)
        Write-Output ("   # ScriptInputFile:`t`t`t[{0}]" -f $RequestBody.ScriptInputFile)
        Write-Output ("   # ScriptBlock:`t`t`t[{0}]" -f $RequestBody.ScriptBlock)
        Write-Output ("   # VMName:`t`t`t`t[{0}]" -f $RequestBody.VMName)
        Write-Output ("   # VMResourceGroupName:`t`t[{0}]" -f $RequestBody.VMResourceGroupName)
        Write-Output ("   # ArcMachine:`t`t`t`[{0}]" -f $RequestBody.ArcMachine)
        Write-Output ("   # Debug:`t`t`t`t`[{0}]" -f $RequestBody.Debug)
        Write-Output ("   {0}" -f ('#' * 72))
        #endregion Show variable information

        ##################################################################
        # Azure Authentication
        ##################################################################
        #region Azure Authentication

        Write-Output ("   {0}" -f ('-' * 72))
        Write-Output '   * Azure Authentication'

        if ($RunAsRunbook) {
            if ($RequestBody.Debug) {
                Write-Output '     * Running in Azure Automation'
            }

            # This requires a RunAs account
            $ServicePrincipalConnection = Get-AutomationConnection -Name 'AzureRunAsConnection'

            Connect-AzAccount `
                -ServicePrincipal `
                -TenantId $ServicePrincipalConnection.TenantId `
                -ApplicationId $ServicePrincipalConnection.ApplicationId `
                -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint `
                -Subscription $RequestBody.SubscriptionId |
            Out-Null
        }
        else {
            if ($RequestBody.Debug) {
                Write-Output '     * Running locally'
            }

            $AzContext = Get-AzContext
            if ($AzContext -and $AzContext.Subscription.Id -ieq $RequestBody.SubscriptionId) {
                Write-Output ("     * Already connected to Azure [{0}][{1}]" -f $AzContext.Tenant.Id, $AzContext.Subscription.Id)
            }
            else {
                # Connect to Azure
                Write-Output ("     * Connect to Azure [{0}]" -f $AzContext.Subscription.Id)
                Connect-AzAccount -SubscriptionId $RequestBody.SubscriptionId | Out-Null
            }
        }

        $AzContext = Get-AzContext

        Write-Output ("   {0}" -f ('-' * 72))

        #endregion Azure Authentication
        ##################################################################

        ##################################################################
        # Storage container
        ##################################################################
        #region Storage container

        Write-Output ("   {0}" -f ('-' * 72))
        Write-Output '   * Storage container'

        # Connect to Storage Account Subscription ID
        if ($AzContext.Subscription.Id -ine $RequestBody.StorageAccountSubscriptionId) {
            Write-Output ("     * Connect to Storage Account Subscription ID [{0}]" -f $RequestBody.StorageAccountSubscriptionId)
            Select-AzSubscription -SubscriptionId $RequestBody.StorageAccountSubscriptionId | Out-Null
            $AzContext = Get-AzContext
        }

        # Get Storage context
        Write-Output '     * Get AZ Storage Account Key'
        $StorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $RequestBody.StorageAccountResourceGroupName -Name $RequestBody.StorageAccountName)[0].value
        Write-Output '     * Create new AZ Storage Context'
        $StorageContext = New-AzStorageContext -StorageAccountName $RequestBody.StorageAccountName -StorageAccountKey $StorageAccountKey

        # Save script block
        if ($RequestBody.ScriptBlock) {
            Write-Output ("     + Upload script (block) [{0}] to Storage Account [{1}] in container [{2}] in folder [{3}]" -f $RequestBody.ScriptFileName, $RequestBody.StorageAccountName, $RequestBody.StorageContainerName, $RequestBody.ScriptFolderName)
            try {
                $Script = $RequestBody.ScriptBlock.ToString().Trim('{}')
                $LocalFile = [System.IO.Path]::GetTempFileName()
                Set-Content $LocalFile -Value $Script

                $params = @{
                    Container = $RequestBody.StorageContainerName
                    Context   = $StorageContext
                }

                $Existing = @()
                $Existing = @( Get-AzStorageBlob @params -ErrorAction Stop )

                if ($Existing.Name -contains ("{0}/{1}" -f $RequestBody.ScriptFolderName, $RequestBody.ScriptFileName)) {
                    Write-Warning -Message ("Script [{0}] in folder [{1}] already exists and will be overwritten" -f $RequestBody.ScriptFileName, $RequestBody.ScriptFolderName)
                }
                $Output = Set-AzStorageBlobContent @params -File $Localfile -Blob ("{0}/{1}" -f $RequestBody.ScriptFolderName, $RequestBody.ScriptFileName) -Force
                if ($Output.Name -notlike ("{0}/{1}" -f $RequestBody.ScriptFolderName, $RequestBody.ScriptFileName)) {
                    Write-Warning -Message ("Set-AzureStorageBlobContent output seems off:`n{0}" -f $($Output | Format-List | Out-String))
                    Stop-Script
                } 
                else {
                    Write-Output ("     * File [{0}] uploaded to Storage Account [{1}] in container [{2}] in folder [{3}]" -f $RequestBody.ScriptFileName, $RequestBody.StorageAccountName, $RequestBody.StorageContainerName, $RequestBody.ScriptFolderName)
                }
            } 
            catch {
                Write-Warning -Message $_
                Write-Warning -Message ("Failed to generate or upload local script for VM [{0}] in Resource Group [{1}]" -f $RequestBody.VMName, $RequestBody.VMResourceGroupName)
                Stop-Script
            }
        }

        Write-Output ("   {0}" -f ('-' * 72))

        #endregion Storage container
        ##################################################################

        ##################################################################
        # Invoking custom script extension
        ##################################################################
        #region Invoking script

        Write-Output ("   {0}" -f ('-' * 72))
        Write-Output '   * Invoking script'

        # Connect to VM Subscription ID
        if ($AzContext.Subscription.Id -ine $RequestBody.SubscriptionId) {
            Write-Output ("     * Connect to VM Subscription ID [{0}]" -f $RequestBody.SubscriptionId)
            Select-AzSubscription -SubscriptionId $RequestBody.SubscriptionID | Out-Null
            $AzContext = Get-AzContext
        }

        $Stopwatch = [system.diagnostics.stopwatch]::new()
        #region ARC Machine
        if ($RequestBody.ArcMachine) {
            Write-Output ("     * VM [{0}] is an ARC machine" -f $RequestBody.VMName)

            #region Check for file
            Write-Output ("     * Check script file [{0}] in folder [{1}] in Storage Container [{2}]" -f $RequestBody.ScriptFileName, $RequestBody.ScriptFolderName, $RequestBody.StorageContainerName)
            $params = @{
                Container = $RequestBody.StorageContainerName
                Context   = $StorageContext
                Blob      = "{0}/{1}" -f $RequestBody.ScriptFolderName, $RequestBody.ScriptFileName
            }

            $Blob = $( Get-AzStorageBlob @params -ErrorAction Stop )
            if ($Blob) {
                $BlobEndpoint = $Blob.Context.BlobEndPoint
            }
            else {
                Write-Warning -Message ("Script file [{0}] in folder [{1}] in Storage Container [{2}] not found" -f $RequestBody.ScriptFileName, $RequestBody.ScriptFolderName, $RequestBody.StorageContainerName)
                Stop-Script
            }
            #endregion Check for file

            #region Generate Shared Access Signature for script file
            Write-Output '     * Generate Shared Access Signature token'
            $StartTime = Get-Date
            $EndTime = $startTime.AddHours(1)
            $Sastoken = New-AzStorageContainerSASToken -Name $RequestBody.StorageContainerName -Permission r -StartTime $StartTime -ExpiryTime $EndTime -context $StorageContext
            #endregion Generate Shared Access Signature for script file

            $ArcVM = Get-AzConnectedMachine -ResourceGroupName $RequestBody.VMResourceGroupName -Name $RequestBody.VMName
            Write-Output ("     * Checking for existing CustomScriptExtension on VM [{0}] in Resource Group [{1}]" -f $ArcVM.Name, $RequestBody.VMResourceGroupName)
            $Extensions = $null
            $Extensions = @( Get-AzConnectedMachineExtension -ResourceGroupName $RequestBody.VMResourceGroupName -MachineName $RequestBody.VMName | Where-Object MachineExtensionType -ieq "CustomScriptExtension" )

            if ($Extensions.count -gt 0) {
                if ($Extensions.Name -notcontains [io.path]::GetFileNameWithoutExtension($RequestBody.ScriptFileName)) {
                    Write-Output ("     * Found CustomScriptExtensions on VM [{0}]:`n{1}" -f $ArcVM.Name, $($Extensions | Format-List | Out-String))
                    foreach ($Extension in $Extensions) {
                        try {
                            Write-Output ("       - Removing CustomScriptExtension [{0}]" -f $Extension.Name)
                            $Stopwatch.Restart()
                            # $Output = Remove-AzConnectedMachineExtension -MachineName $ArcVM.Name -ResourceGroupName $RequestBody.VMResourceGroupName -Name $Extension.Name
                            Remove-AzConnectedMachineExtension -MachineName $ArcVM.Name -ResourceGroupName $RequestBody.VMResourceGroupName -Name $Extension.Name
                            $Stopwatch.Stop()
                            Write-Output ("       - Removed CustomScriptExtension [{0}] - Time Duration: Minutes [{1}] Seconds [{2}]" -f $Extension.Name, $Stopwatch.Elapsed.Minutes , $Stopwatch.Elapsed.Seconds)
                        } 
                        catch {
                            Write-Warning -Message $_
                            Write-Warning -Message ("Failed to remove existing CustomScriptExtension [{0}] from VM [{1}] in ResourceGroup [{2}]" -f $Extensions.Name, $ArcVM.Name, $RequestBody.VMResourceGroupName)
                            continue
                        }
                    }
                }
                else {
                    Write-Output ("     * CustomScriptExtension [{0}] already connected on VM [{1}]" -f [io.path]::GetFileNameWithoutExtension($RequestBody.ScriptFileName), $ArcVM.Name)
                }
            }
            else {
                Write-Output '     * No CustomScriptExtension found'
            }

            # Script in place, set up an extension!
            Write-Output ("     * Adding CustomScriptExtension [{0}\{1}] to VM [{2}] in Resource Group [{3}]" -f $RequestBody.ScriptFolderName, $RequestBody.ScriptFileName, $ArcVM.Name, $RequestBody.VMResourceGroupName)
            
            try {
                $FileUris = @($("{0}{1}/{2}/{3}{4}" -f $BlobEndpoint, $RequestBody.StorageContainerName, $RequestBody.ScriptFolderName, $RequestBody.ScriptFileName, $SasToken))
                $CommandToExecute = "powershell -ExecutionPolicy Unrestricted -File {0}\{1}" -f $RequestBody.ScriptFolderName, $RequestBody.ScriptFileName

                if ($RequestBody.ScriptInputFile) {
                    $FileUris += @($("{0}{1}/{2}/{3}{4}" -f $BlobEndpoint, $RequestBody.StorageContainerName, $RequestBody.ScriptFolderName, $RequestBody.ScriptInputFile, $SasToken))
                    $CommandToExecute += " -InputFile {0}\{1}" -f $RequestBody.ScriptFolderName, $RequestBody.ScriptInputFile
                }

                $Settings = @{
                    fileUris = $FileUris
                    commandToExecute = $CommandToExecute
                }

                $Params = @{
                    Name              = [io.path]::GetFileNameWithoutExtension($RequestBody.ScriptFileName)
                    ResourceGroupName = $RequestBody.VMResourceGroupName
                    MachineName       = $ArcVM.Name
                    Location          = $ArcVM.location
                    Publisher         = "Microsoft.Compute"
                    Setting           = $Settings
                    ExtensionType     = "CustomScriptExtension"
                    ForceRerun        = $true
                }

                $Stopwatch.Restart()
                $Output = New-AzConnectedMachineExtension @Params
                $Stopwatch.Stop()
                Write-Output ("     * Added CustomScriptExtension [{0}] - Time Duration: Minutes [{1}] Seconds [{2}]" -f $RequestBody.ScriptFileName, $Stopwatch.Elapsed.Minutes , $Stopwatch.Elapsed.Seconds)

                if ($Output.StatusCode -ine 'success') {
                    Write-Warning -Message ("New-AzConnectedMachineExtension output seems off:`n{0}" -f $($Output | Format-List | Out-String))
                    Stop-Script
                }
            } 
            catch {
                Write-Warning -Message $_
                Write-Warning -Message ("Failed to set CustomScriptExtension [{0}] to VM [{1}] in Resource Group [{2}]" -f $RequestBody.ScriptFileName, $aRCvm.Name, $RequestBody.ResourceGroupName)
                continue
            }
        }
        #endregion ARC Machine

        #region Azure Virtual Machine
        else {
            Write-Output ("     * VM [{0}] is an Azure Virtual Machine" -f $RequestBody.VMName)
            $AzVM = Get-AzVM -Name $RequestBody.VMName -Status
            if ($AzVM.PowerState -ne 'VM running') {
                Write-Warning -Message ("VM [{0}] is not running!" -f $RequestBody.VMName)
                Stop-Script
            }

            $AzVMExtended = Get-AzVM -ResourceGroupName $RequestBody.VMResourceGroupName -Name $RequestBody.VMName -Status -ErrorAction Stop
            Write-Output ("     * Checking for existing CustomScriptExtension on VM [{0}] in Resource Group [{1}]" -f $AzVM.Name, $AzVM.ResourceGroupName)
            $Extensions = $null
            $Extensions = @( $AzVMExtended.Extensions | Where-Object { $_.Type -like 'Microsoft.Compute.CustomScriptExtension' } )
            if ($Extensions.count -gt 0) {
                Write-Output ("     * Found CustomScriptExtensions on VM [{0}]:`n{1}" -f $AzVM.Name, $($Extensions | Format-List | Out-String))
                try {
                    foreach ($Extension in $Extensions) {
                        Write-Output ("       - Removing CustomScriptExtension [{0}]" -f $Extension.Name)
                        $Stopwatch.Restart()
                        $Output = Remove-AzVMCustomScriptExtension -VMName $RequestBody.VMName -ResourceGroupName $AzVM.ResourceGroupName -Name $Extension.Name -Force -ErrorAction Stop
                        $Stopwatch.Stop()
                        Write-Output ("       - Removed CustomScriptExtension [{0}] - Time Duration: Minutes [{1}] Seconds [{2}]" -f $Extension.Name, $Stopwatch.Elapsed.Minutes , $Stopwatch.Elapsed.Seconds)
            
                        if ($Output.StatusCode -notlike 'OK') {
                            Write-Warning -Message ("Remove-AzVMCustomScriptExtension output seems off:`n{0}" -f $($Output | Format-List | Out-String))
                            Stop-Script
                        }
                    }
                }
                catch {
                    Write-Warning -Message $_
                    Write-Warning -Message ("Failed to remove existing CustomScriptExtension [{0}] from VM [{1}] in ResourceGroup [{2}]" -f $Extensions.Name, $AzVM.Name, $AzVM.ResourceGroupName)
                    continue
                }
            }
            else {
                Write-Output '     * No CustomScriptExtension found'
            }

            # Script in place, set up an extension!
            Write-Output ("     * Adding CustomScriptExtension [{0}\{1}] to VM [{2}] in Resource Group [{3}]" -f $RequestBody.ScriptFolderName, $RequestBody.ScriptFileName, $AzVM.Name, $AzVM.ResourceGroupName)
            try {
                $Stopwatch.Restart()
                $Output = Set-AzVMCustomScriptExtension -ResourceGroupName  $AzVM.ResourceGroupName `
                                                        -VMName  $AzVM.Name `
                                                        -Location $AzVM.Location `
                                                        -FileName ("{0}\{1}" -f $RequestBody.ScriptFolderName, $RequestBody.ScriptFileName) `
                                                        -Run ("{0}\{1}" -f $RequestBody.ScriptFolderName, $RequestBody.ScriptFileName) `
                                                        -ContainerName $RequestBody.StorageContainerName `
                                                        -StorageAccountName $RequestBody.StorageAccountName `
                                                        -StorageAccountKey $StorageAccountKey `
                                                        -Name $([io.path]::GetFileNameWithoutExtension($RequestBody.ScriptFileName))
                $Stopwatch.Stop()
                Write-Output ("     * Added CustomScriptExtension [{0}] - Time Duration: Minutes [{1}] Seconds [{2}]" -f $RequestBody.ScriptFileName, $Stopwatch.Elapsed.Minutes , $Stopwatch.Elapsed.Seconds)

                if ($Output.StatusCode -ne 'OK') {
                    Write-Warning -Message ("Set-AzureRmVMCustomScriptExtension output seems off:`n" -f $($Output | Format-List | Out-String))
                    Stop-Script
                }
            } 
            catch {
                Write-Warning -Message $_
                Write-Warning -Message ("Failed to set CustomScriptExtension [{0}] to VM [{1}] in Resource Group [{2}]" -f $RequestBody.ScriptFileName, $AzVM.Name, $AzVM.ResourceGroupName)
                continue
            }
        }
        #endregion Azure Virtual Machine

        Write-Output ("   {0}" -f ('-' * 72))


        #endregion Invoking script
        ##################################################################
    }
    else {
        Write-Warning -Message ("Runbook [{0}] was not started from Webhook (RequestBody is not available or empty)" -f $RunbookName)
    }
}
else {
    Write-Warning -Message ("Runbook [{0}] was not started from Webhook (WebHookData is not available or empty)" -f $RunbookName)
}

Write-Output (" * End [{0}]" -f $RunbookName)

Write-Output ('-' * 75)

#endregion Main
##################################################################
