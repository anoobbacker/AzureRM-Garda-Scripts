<#
.DESCRIPTION
    This script scans the devices updates.
     
.PARAMS 

    SubscriptionId: Specifies the ID of the subscription.
    DeviceName: Specifies the name of the StorSimple device on which to create/update the volume.
    ResourceGroupName: Specifies the name of the resource group on which to create/update the volume.
    ManagerName: Specifies the name of the resource (StorSimple device manager) on which to create/update the volume.

#>

Param
(
    [parameter(Mandatory = $true, HelpMessage = "Specifies the ID of the subscription.")]
    [String]
    $SubscriptionId,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the name of the StorSimple device on which to create/update the volume.")]
    [String]
    $DeviceName,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the name of the resource group on which to create/update the volume.")]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the name of the resource (StorSimple device manager) on which to create/update the volume.")]
    [String]
    $ManagerName
)

#Load all required assemblies
$Assembly = [System.Reflection.Assembly]::LoadFrom("E:\WorkFolders\StorSimple\AzureRM\AzureRM.StorSimpleCmdlets\packages\Microsoft.IdentityModel.Clients.ActiveDirectory.2.28.3\lib\net45\Microsoft.IdentityModel.Clients.ActiveDirectory.dll")
$Assembly = [System.Reflection.Assembly]::LoadFrom("E:\WorkFolders\StorSimple\AzureRM\AzureRM.StorSimpleCmdlets\AzureRM.StorSimpleCmdlets\Dependencies\Microsoft.Rest.ClientRuntime.Azure.dll")
$Assembly = [System.Reflection.Assembly]::LoadFrom("E:\WorkFolders\StorSimple\AzureRM\AzureRM.StorSimpleCmdlets\AzureRM.StorSimpleCmdlets\Dependencies\Microsoft.Rest.ClientRuntime.dll")
$Assembly = [System.Reflection.Assembly]::LoadFrom("E:\WorkFolders\StorSimple\AzureRM\AzureRM.StorSimpleCmdlets\AzureRM.StorSimpleCmdlets\Dependencies\Newtonsoft.Json.dll")
$Assembly = [System.Reflection.Assembly]::LoadFrom("E:\WorkFolders\StorSimple\AzureRM\AzureRM.StorSimpleCmdlets\packages\Microsoft.Rest.ClientRuntime.Azure.Authentication.2.2.9-preview\lib\net45\Microsoft.Rest.ClientRuntime.Azure.Authentication.dll")
$Assembly = [System.Reflection.Assembly]::LoadFrom("E:\WorkFolders\StorSimple\AzureRM\AzureRM.StorSimpleCmdlets\AzureRM.StorSimpleCmdlets\Dependencies\Microsoft.Azure.Management.Storsimple8000series.dll")

# Print methods
Function PrettyWriter($Content, $Color = "Yellow") { 
    Write-Host $Content -Foregroundcolor $Color 
}

# Define constant variables (DO NOT CHANGE BELOW VALUES)
$FrontdoorUrl = "urn:ietf:wg:oauth:2.0:oob"
$TokenUrl = "https://management.azure.com"
$TenantId = "1950a258-227b-4e31-a9cf-717495945fc2"
$DomainId = "72f988bf-86f1-41af-91ab-2d7cd011db47"

$FrontdoorUri = New-Object System.Uri -ArgumentList $FrontdoorUrl
$TokenUri = New-Object System.Uri -ArgumentList $TokenUrl

$AADClient = [Microsoft.Rest.Azure.Authentication.ActiveDirectoryClientSettings]::UsePromptOnly($TenantId, $FrontdoorUri)

# Set Synchronization context
$SyncContext = New-Object System.Threading.SynchronizationContext
[System.Threading.SynchronizationContext]::SetSynchronizationContext($SyncContext)

# Verify User Credentials
$Credentials = [Microsoft.Rest.Azure.Authentication.UserTokenProvider]::LoginWithPromptAsync($DomainId, $AADClient).GetAwaiter().GetResult()
$StorSimpleClient = New-Object Microsoft.Azure.Management.StorSimple8000Series.StorSimple8000SeriesManagementClient -ArgumentList $TokenUri, $Credentials

# Set SubscriptionId
$StorSimpleClient.SubscriptionId = $SubscriptionId

try {
    # Scans device updates
    [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::ScanForUpdates($StorSimpleClient.Devices, $DeviceName, $ResourceGroupName, $ManagerName)

    # Reads update summary
    $UpdateSummary = [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::GetUpdateSummary($StorSimpleClient.Devices, $DeviceName, $ResourceGroupName, $ManagerName)
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}

if ($UpdateSummary.RegularUpdatesAvailable -and $UpdateSummary.IsUpdateInProgress) {
    PrettyWriter "Download and install of software updates in progress."
} elseif ($UpdateSummary.RegularUpdatesAvailable) {
    PrettyWriter "New updates are available.`nLast updated on: $($UpdateSummary.LastUpdatedTime.ToString('ddd MMM dd yyyy'))"
} else {
    PrettyWriter "Your device ($($DeviceName)) is up-to-date.`nLast updated on: $($UpdateSummary.LastUpdatedTime.ToString('ddd MMM dd yyyy'))"
}
