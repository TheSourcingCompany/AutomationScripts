
<#PSScriptInfo

.VERSION 1.3

.GUID 5fbe9d16-981d-4a88-874c-365d46c1fcc2

.AUTHOR zachal

.COMPANYNAME Microsoft

.COPYRIGHT

.TAGS UpdateManagement, Automation

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES ThreadJob

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
Removed parameters AutomationAccount, ResourceGroup

.PRIVATEDATA

#>

<#

.DESCRIPTION
 This script is intended to be run as a part of Update Management Pre/Post scripts.


It requires a RunAs account and the usage of the Turn On VMs script as a pre-deployment script.


This script will ensure all Azure VMs in the Update Deployment are turned off after they recieve updates.


This script reads the name of machines that were started by Update Management via the Turn On VMs script


#>

#requires -Modules ThreadJob
<#
.SYNOPSIS
 Start VMs as part of an Update Management deployment

.DESCRIPTION
  This script is intended to be run as a part of Update Management Pre/Post scripts.
  It requires a RunAs account.
  This script will ensure all Azure VMs in the Update Deployment are running so they recieve updates.
  This script will store the names of machines that were started in an Automation variable so only those machines
  are turned back off when the deployment is finished (UpdateManagement-TurnOffVMs.ps1)

.PARAMETER SoftwareUpdateConfigurationRunContext
  This is a system variable which is automatically passed in by Update Management during a deployment.

#>

param(
    [string]$SoftwareUpdateConfigurationRunContext
)


#region BoilerplateAuthentication
#This requires a RunAs account
$ServicePrincipalConnection = Get-AutomationConnection -Name 'AzureRunAsConnection'

Add-AzAccount `
    -ServicePrincipal `
    -TenantId $ServicePrincipalConnection.TenantId `
    -ApplicationId $ServicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint

$AzureContext = Select-AzSubscription -SubscriptionId $ServicePrincipalConnection.SubscriptionID
#endregion BoilerplateAuthentication


#If you wish to use the run context, it must be converted from JSON
$context = ConvertFrom-Json  $SoftwareUpdateConfigurationRunContext
$vmIds = $context.SoftwareUpdateConfigurationSettings.AzureVirtualMachines
$runId = "PrescriptContext" + $context.SoftwareUpdateConfigurationRunId

if (!$vmIds) {
    #Workaround: Had to change JSON formatting
    $Settings = ConvertFrom-Json $context.SoftwareUpdateConfigurationSettings
    #Write-Output "List of settings: $Settings"
    $VmIds = $Settings.AzureVirtualMachines
    #Write-Output "Azure VMs: $VmIds"
    if (!$vmIds) {
        Write-Output "No Azure VMs found"
        return
    }
}

#https://github.com/azureautomation/runbooks/blob/master/Utility/ARM/Find-WhoAmI
# In order to prevent asking for an Automation Account name and the resource group of that AA,
# search through all the automation accounts in the subscription
# to find the one with a job which matches our job ID
$AutomationResource = Get-AzResource -ResourceType Microsoft.Automation/AutomationAccounts

foreach ($Automation in $AutomationResource) {
    $Job = Get-AzAutomationJob -ResourceGroupName $Automation.ResourceGroupName -AutomationAccountName $Automation.Name -Id $PSPrivateMetadata.JobId.Guid -ErrorAction SilentlyContinue
    if (!([string]::IsNullOrEmpty($Job))) {
        $ResourceGroup = $Job.ResourceGroupName
        $AutomationAccount = $Job.AutomationAccountName
        break;
    }
}

#This is used to store the state of VMs
New-AzAutomationVariable -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -Name $runId -Value "" -Encrypted $false

$updatedMachines = @()
$startableStates = "stopped" , "stopping", "deallocated", "deallocating"
$jobIDs = New-Object System.Collections.Generic.List[System.Object]

#Parse the list of VMs and start those which are stopped
#Azure VMs are expressed by:
# subscription/$subscriptionID/resourcegroups/$resourceGroup/providers/microsoft.compute/virtualmachines/$name
$vmIds | ForEach-Object {
    $vmId = $_

    $split = $vmId -split "/";
    $subscriptionId = $split[2];
    $rg = $split[4];
    $name = $split[8];
    Write-Output ("Subscription Id: " + $subscriptionId)
    Select-AzSubscription -Subscription $subscriptionId
    Write-Output ("ResourceGroupName: " + $rg)

    $vm = Get-AzVM -ResourceGroupName $rg -Name $name -Status

    #Query the state of the VM to see if it's already running or if it's already started
    $state = ($vm.Statuses[1].DisplayStatus -split " ")[1]
    if ($state -in $startableStates) {
        Write-Output "Starting '$($name)' ..."
        #Store the VM we started so we remember to shut it down later
        $updatedMachines += $vmId
        $newJob = Start-ThreadJob -ScriptBlock { param($resource, $vmname) Start-AzVM -ResourceGroupName $resource -Name $vmname } -ArgumentList $rg, $name
        $jobIDs.Add($newJob.Id)
    } else {

        [System.String]$ScriptBlock = {


            function Test-PendingReboot {
                param (
                    [CmdletBinding()]
                    # ComputerName is optional. If not specified, localhost is used.
                    [ValidateNotNullOrEmpty()]
                    [string[]]$ComputerName = $env:COMPUTERNAME,

                    [Parameter()]
                    [pscredential]$Credential

                )



                $ErrorActionPreference = 'Stop'

                $scriptBlock = {
                    if ($null -ne $using) {
                        # $using is only available if this is being called with a remote session
                        $VerbosePreference = $using:VerbosePreference
                    }

                    function Test-RegistryKey {
                        [OutputType('bool')]
                        [CmdletBinding()]
                        param
                        (
                            [Parameter(Mandatory)]
                            [ValidateNotNullOrEmpty()]
                            [string]$Key
                        )

                        $ErrorActionPreference = 'Stop'

                        if (Get-Item -Path $Key -ErrorAction Ignore) {
                            $true
                        }
                    }

                    function Test-RegistryValue {
                        [OutputType('bool')]
                        [CmdletBinding()]
                        param
                        (
                            [Parameter(Mandatory)]
                            [ValidateNotNullOrEmpty()]
                            [string]$Key,

                            [Parameter(Mandatory)]
                            [ValidateNotNullOrEmpty()]
                            [string]$Value
                        )

                        $ErrorActionPreference = 'Stop'

                        if (Get-ItemProperty -Path $Key -Name $Value -ErrorAction Ignore) {
                            $true
                        }
                    }

                    function Test-RegistryValueNotNull {
                        [OutputType('bool')]
                        [CmdletBinding()]
                        param
                        (
                            [Parameter(Mandatory)]
                            [ValidateNotNullOrEmpty()]
                            [string]$Key,

                            [Parameter(Mandatory)]
                            [ValidateNotNullOrEmpty()]
                            [string]$Value
                        )

                        $ErrorActionPreference = 'Stop'

                        if (($regVal = Get-ItemProperty -Path $Key -Name $Value -ErrorAction Ignore) -and $regVal.($Value)) {
                            $true
                        }
                    }

                    # Added "test-path" to each test that did not leverage a custom function from above since
                    # an exception is thrown when Get-ItemProperty or Get-ChildItem are passed a nonexistant key path
                    $tests = @(
                        { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' }
                        { Test-RegistryKey -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress' }
                        { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' }
                        { Test-RegistryKey -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending' }
                        { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting' }
                        { Test-RegistryValueNotNull -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Value 'PendingFileRenameOperations' }
                        { Test-RegistryValueNotNull -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Value 'PendingFileRenameOperations2' }
                        {
                            # Added test to check first if key exists, using "ErrorAction ignore" will incorrectly return $true
                            'HKLM:\SOFTWARE\Microsoft\Updates' | Where-Object { test-path $_ -PathType Container } | ForEach-Object {
                                if (Test-Path "$_\UpdateExeVolatile" ) {
                    (Get-ItemProperty -Path $_ -Name 'UpdateExeVolatile' | Select-Object -ExpandProperty UpdateExeVolatile) -ne 0
                                } else {
                                    $false
                                }
                            }
                        }
                        { Test-RegistryValue -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Value 'DVDRebootSignal' }
                        { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentRebootAttempts' }
                        { Test-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon' -Value 'JoinDomain' }
                        { Test-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon' -Value 'AvoidSpnSet' }
                        {
                            # Added test to check first if keys exists, if not each group will return $Null
                            # May need to evaluate what it means if one or both of these keys do not exist
            ( 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' | Where-Object { test-path $_ } | % { (Get-ItemProperty -Path $_ ).ComputerName } ) -ne
            ( 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' | Where-Object { Test-Path $_ } | % { (Get-ItemProperty -Path $_ ).ComputerName } )
                        }
                        {
                            # Added test to check first if key exists
                            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending' | Where-Object {
                (Test-Path $_) -and (Get-ChildItem -Path $_) } | ForEach-Object { $true }
                        }
                    )

                    foreach ($test in $tests) {
                        Write-Verbose "Running scriptblock: [$($test.ToString())]"
                        if (& $test) {
                            $true
                            break
                        }
                    }
                }

                # if ComputerName was not specified, then use localhost
                # to ensure that we don't create a Session.
                if ($null -eq $ComputerName) {
                    $ComputerName = "localhost"
                }

                foreach ($computer in $ComputerName) {
                    try {
                        $connParams = @{
                            'ComputerName' = $computer
                        }
                        if ($PSBoundParameters.ContainsKey('Credential')) {
                            $connParams.Credential = $Credential
                        }

                        $output = @{
                            ComputerName    = $computer
                            IsPendingReboot = $false
                        }

                        if ($computer -in ".", "localhost", $env:COMPUTERNAME ) {
                            if (-not ($output.IsPendingReboot = Invoke-Command -ScriptBlock $scriptBlock)) {
                                $output.IsPendingReboot = $false
                            }
                        } else {
                            $psRemotingSession = New-PSSession @connParams

                            if (-not ($output.IsPendingReboot = Invoke-Command -Session $psRemotingSession -ScriptBlock $scriptBlock)) {
                                $output.IsPendingReboot = $false
                            }
                        }
                        [pscustomobject]$output
                    } catch {
                        Write-Error -Message $_.Exception.Message
                    } finally {
                        if (Get-Variable -Name 'psRemotingSession' -ErrorAction Ignore) {
                            $psRemotingSession | Remove-PSSession
                        }
                    }
                }

            }

            $PendingReboot = Test-PendingReboot

            if ($PendingReboot.IsPendingReboot) {

                Return $true


            } else {
                Return $false
            }

        }

        $FileName = "RunScript.ps1"
        Out-File -FilePath $FileName -InputObject $ScriptBlock -NoNewline -Force
        $Result = Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -CommandId 'RunPowerShellScript' -ScriptPath $FileName
        Remove-Item -Path $FileName -Force -ErrorAction SilentlyContinue


        if ($([System.Convert]::ToBoolean($($Result[0].Value[0].Message))) -ieq $true) {

            Write-Output ("Reboot for VM: {0} is pending" -f $vm.Name)

            Restart-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Verbose

            Write-Output ("Rebooted VM: {0}" -f $vm.Name)


        } else {

            Write-Output ("Reboot for VM: {0} is NOT pending" -f $vm.Name)

        }


    }
}

$updatedMachinesCommaSeperated = $updatedMachines -join ","
#Wait until all machines have finished starting before proceeding to the Update Deployment
$jobsList = $jobIDs.ToArray()
if ($jobsList) {
    Write-Output "Waiting for machines to finish starting..."
    Wait-Job -Id $jobsList
}

foreach ($id in $jobsList) {
    $job = Get-Job -Id $id
    if ($job.Error) {
        Write-Output $job.Error
    }

}

Write-output $updatedMachinesCommaSeperated
#Store output in the automation variable
Set-AutomationVariable -Name $runId -Value $updatedMachinesCommaSeperated

Start-Sleep -Seconds 600

Write-Output "Finished TurnOn VM script"
