#Add-PSSnapin VMware*
#Connect-VIServer -Server VDCvcenter
param
(
	[alias("d")]
	$directory =  "C:\utils\Migration\VDC",
	[alias("dc")]
	$datacenter = "VDC"
)

function Set-DatastoreClusterDefaultIntraVmAffinity{ 
    param( 
        [CmdletBinding()] 
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)] 
        [PSObject]$DSC, 
        [Switch]$Enabled 
     )

      process{ 
        $SRMan = Get-View StorageResourceManager 
        if($DSC.GetType().Name -eq "string"){ 
          $DSC = Get-DatastoreCluster -Name $DSC | Get-View 
        } 
        elseif($DSC.GetType().Name -eq "DatastoreClusterImpl"){ 
          $DSC = Get-DatastoreCluster -Name $DSC.Name | Get-View 
        } 
            $spec = New-Object VMware.Vim.StorageDrsConfigSpec 
            $spec.podConfigSpec = New-Object VMware.Vim.StorageDrsPodConfigSpec 
            $spec.podConfigSpec.DefaultIntraVmAffinity = $Enabled 
            $SRMan.ConfigureStorageDrsForPod($DSC.MoRef, $spec, $true) 
    } 
}



$directory = $directory.trim("\")
new-item $directory -type directory -erroraction silentlycontinue
$dc = get-datacenter $datacenter
$StorageDRS = $dc | Get-DatastoreCluster
$Datastores = $dc | Get-Datastore
$dc | get-folder | where {$_.type -eq "datastore"} | select name,parent | export-clixml $directory\Storagefolders.xml

$folders = Get-Folder | where {$_.Type -eq "datastore"}
$rootStorageFolder = Get-Folder | where {$_.type -eq "datastore" -and $_.Parent.Name -eq $dc.Name}

foreach($Cluster in $StorageDRS){
$findClusterParent = $Cluster.ExtensionData.Parent.value
    foreach($folder in $folders){
    $DatastoreClusterLocation = @()
        IF($folder.Id -match $findClusterParent){
            DO {
                $DatastoreClusterLocation += $Cluster.Name
                $DatastoreClusterLocation += $folder.Name
                $folder = $folder.Parent.Name
                }
            Until($folder -eq "datastore")
            $DatastoreClusterLocation += $rootStorageFolder.Name
            $DatastoreCLusterLocation -join "," >>$directory\StorageClusterLocations.csv          
        }
    }
$Cluster | select Name,IOLatencyThresholdMillisecond,IOLoadBalanceEnabled,SdrsAutomationLevel,SpaceUtilizationThresholdPercent | Export-Csv -Path $directory\StorageClusterSettings.csv -Append -NoTypeInformation
$datastoreLocations = @()
$datastores = $Cluster | Get-Datastore
$datastoreLocations += $Cluster.Name
$datastoreLocations += $datastores.Name
$datastoreLocations -join "," >>$directory\ClusterDatastoreLocations.csv
Get-DatastoreCluster | Select Name, @{N="DefaultIntraVmAffinity";E={($_ | Get-View).PodStorageDRSEntry.StorageDRSConfig.PodConfig.DefaultIntraVmAffinity}} | Export-CSV -Path $directory\StorageClusterVMAffinity.csv -Append -NoTypeInformation
}
#XML Out of all Datastores not associated with Datastore Cluster
$dc | get-datastore | select name,ParentFolder | export-clixml $directory\datastore-locations.xml

<#the hard way of getting all datastore locations..

foreach($Datastore in $Datastores){

$findDatastoreParent = $Datastore.ExtensionData.Parent.value
    foreach($folder in $folders){
    $DatastoreLocation = @()
        IF($folder.ExtentionData.MoRef.Value -match $findDatastoreParent){
            write-host $folder, $datastore
            DO {
                $DatastoreLocation += $Datastore.Name
                $DatastoreLocation += $folder.Name
                $folder = $folder.Parent.Name
                }
            Until($folder -eq "datastore")
            $DatastoreLocation += $rootStorageFolder.Name
            $DatastoreLocation -join "," >>$directory\StorageLocations.csv          
        }
    }
}#>