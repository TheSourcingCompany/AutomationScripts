workflow StartStopByTag
{
        Param(
        [Parameter(Mandatory=$true)]
        [String]
        $TagName,
        [Parameter(Mandatory=$true)]
        [String]
        $TagValue,
        [Parameter(Mandatory=$true)]
        [Boolean]
        $Shutdown
        )
     
    $connectionName = "AzureRunAsConnection";
 
    try
    {
        # Get the connection "AzureRunAsConnection "
        $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName        
 
        "Logging in to Azure..."
        Add-AzAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    }
    catch {
 
        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        } else{
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }

$AllSubID = (Get-AzSubscription).SubscriptionId
Write-Output "$(Get-Date -format s) :: List of Subscription below"
$AllSubID

$AllVMList = @()

Foreach ($SubID in $AllSubID) {
Select-AzSubscription -Subscriptionid "$SubID"

#Region Check Resource Groups

$tag = @{$tagname=$tagvalue}
$ResourcegGroupWithTag = Get-AzResourceGroup -Tag $tag

if ($ResourcegGroupWithTag){

foreach ($RG in $ResourcegGroupWithTag){

$UnderlyingVMs = Get-AzVM -ResourceGroupName $RG.ResourceGroupName

foreach ($vm in $UnderlyingVMs){

 $VMObject = Get-azResource -ResourceId $vm.Id

 	$SelectedVM = New-Object psobject -Property @{`
		"Subscriptionid" = $SubID;
		"ResourceGroupName" = $VM.ResourceGroupName;
		"TagValue" = $tag[$tagname];
		"VMName" = $VM.Name}
		$AllVMList += $SelectedVM

    }

}

}

#endregion

#region Check VMs

$VMsWithTag = Get-azResource | where-object {$_.ResourceType -like "Microsoft.Compute/virtualMachines" -and $_.Tags.Keys -ieq $TagName -and $_.Tags.Values -eq $TagValue}

Foreach ($VM in $VMsWithTag) {
	$SelectedVM = New-Object psobject -Property @{`
		"Subscriptionid" = $SubID;
		"ResourceGroupName" = $VM.ResourceGroupName;
		"TagValue" = $VM.tags.$TagName;
		"VMName" = $VM.Name}
		$AllVMList += $SelectedVM
		}
#endregion

}

Write-Output "$(Get-Date -format s) :: VM start list"
$AllVMList

Foreach ($VM in $AllVMList) {
	Write-Output "$(Get-Date -format s) :: Start VM: $($VM.VMName) :: $($VM.ResourceGroupName) :: $($VM.Subscriptionid)"
	Select-AzSubscription -Subscriptionid $VM.Subscriptionid
        if($Shutdown){
            Write-Output "Stopping $($vm.Name)";        
            Stop-AzVm -Name $vm.VMName -ResourceGroupName $vm.ResourceGroupName -Force;
        }
        else{
            Write-Output "Starting $($vm.Name)";        
            Start-AzVm -Name $vm.VMName -ResourceGroupName $vm.ResourceGroupName;
        }
}



     if($Shutdown){
Write-Output "$(Get-Date -format s) :: Done VM stop"
     }

             else{
Write-Output "$(Get-Date -format s) :: Done VM start"
        }




}
