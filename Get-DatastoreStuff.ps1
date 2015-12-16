#Add-PSSnapin VMware*
#Connect-VIServer -Server goldvc1p
param
(
	[alias("d")]
	$directory =  "E:\tmp\GOLD\",
	[alias("dc")]
	$datacenter = "GOLD"
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
            $DatastoreClusterLocation += $Cluster.Name
            DO {
                $DatastoreClusterLocation += $folder.Name
                IF($folder.Name -ne $rootStorageFolder){
                $folder = $folder.Parent.Name
                }
                }
            Until($folder.name -eq "datastore")
            $DatastoreCLusterLocation -join "," >>$directory\StorageClusterLocations.csv          
        }
    }
$Cluster | select Name,IOLatencyThresholdMillisecond,IOLoadBalanceEnabled,SdrsAutomationLevel,SpaceUtilizationThresholdPercent | Export-Csv -Path $directory\StorageClusterSettings.csv -Append -NoTypeInformation
$ClusterDatastoreLocations = @()
$Clusterdatastores = $Cluster | Get-Datastore
$ClusterDatastoreLocations += $Cluster.Name
$ClusterDatastoreLocations += $datastores.Name
$ClusterDatastoreLocations -join "," >>$directory\ClusterDatastoreLocations.csv
Get-DatastoreCluster | Select Name, @{N="DefaultIntraVmAffinity";E={($_ | Get-View).PodStorageDRSEntry.StorageDRSConfig.PodConfig.DefaultIntraVmAffinity}} | Export-CSV -Path $directory\StorageClusterVMAffinity.csv -Append -NoTypeInformation
}

#the hard way of getting all datastore locations..

foreach($Datastore in $Datastores){
$findDatastoreParent = $Datastore.ExtensionData.Parent.value
    foreach($folder in $folders){
    $DatastoreLocation = @()
        IF($folder.Id -match $findDatastoreParent){
            $DatastoreLocation += $Datastore.Name
            DO {
                $DatastoreLocation += $folder.Name
                IF($folder.Name -ne $rootStorageFolder){
                $folder = $folder.Parent
                }
                IF($folder.Name -eq $rootStorageFolder){
                $DatastoreLocation += $rootStorageFolder
                }
                }
            Until($folder.Name -eq "datastore")
            $DatastoreLocation -join "," >>$directory\DatastoreLocations.csv          
        }
    }
}