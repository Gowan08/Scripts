#Add-PSSnapin VMware*
param
(
	[alias("d")]
	$directory =  "C:\utils\Migration\VDC\",
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

#Create Folder Structure for Storage
foreach ($thisFolder in (import-clixml $directory\Storagefolders.xml | where {!($_.name -eq "datastore")})) {(get-datacenter $datacenter) | get-folder $thisFolder.Parent | new-folder $thisFolder.Name -confirm:$false}
#Set Header to be 128...maximum of storage cluster
$header = 0..128
#Gather all csv's from Get-DatastoreStuff.ps1
$DSCLocation = "StorageClusterLocations.csv"
$DSCConfig = "StorageClusterSettings.csv"
$DLocations = "ClusterDatastoreLocations.csv"
$VMAffinity = "StorageClusterVMAffinity.csv"
#send all csv information to variables
$StorageClusterLocations = Import-CSV "$directory\$DSCLocation" -delimiter "," -header $header
$StorageCLusterSettings = Import-CSV "$directory\$DSCConfig"
$DatastoreLocations = Import-CSV "$directory\$DLocations" -delimiter "," -header $header
$VMAffinitySettings = Import-CSV "$directory\$VMAffinity"
#Create Storage Clusters through a means of complicated methods..done to ensure the right folder is selected, and not in another directory with the same name on accident.
foreach($line in $StorageClusterLocations){
    $y = 1
    $ClusterName = $line.0
    DO{
      IF($line.$y -notMatch "datastore"){$y++}
      IF($line.1 -match "datastore"){$y=0}
      }
    Until ($line.$y -match "datastore" -or $y -eq 0)
    
    If($y -eq 0){
    $root = $line.1
    New-DatastoreCluster -Name $ClusterName -Location $root
    }
    Else{
    $count = $y-1
    foreach($value in $count){
        $root = $line.$y
        $folder = Get-Folder -Name $line.$count | where {$_.Parent.Name -eq $root} 
        DO{
        If($line.1 -ne $folder){
        $root = $folder
        $count = $count - 1
        $folder = Get-Folder -Name $line.$count | where {$_.Parent.Name -eq $root} 
        }
        }
        Until($line.1 -eq $folder)
        }
        New-DatastoreCluster -Name $ClusterName -Location $folder
        }
    }
#Set Datastore Cluster Captured Settings from CSV
foreach($setting in $StorageCLusterSettings){
$IOLBEnabled = [System.Convert]::ToBoolean($Setting.IOLoadBalanceEnabled)
Set-DatastoreCluster -DatastoreCluster $Setting.Name -IOLatencyThresholdMillisecond $Setting.IOLatencyThresholdMillisecond -IOLoadBalanceEnabled $IOLBEnabled -SdrsAutomationLevel $Setting.SdrsAutomationLevel -SpaceUtilizationThresholdPercent $Setting.SpaceUtilizationThresholdPercent
}
#Set Intra VM Affinity Settings within each DS Cluster from CSV Capture
 foreach($line in $VMAffinitySettings){
    if($line.DefaultIntraVmAffinity -eq "False"){
    Get-DatastoreCluster -Name $line.Name | Set-DatastoreClusterDefaultIntraVmAffinity
    }
 }
#Get-DatastoreCluster | Select Name, @{N="DefaultIntraVmAffinity";E={($_ | Get-View).PodStorageDRSEntry.StorageDRSConfig.PodConfig.DefaultIntraVmAffinity}}

<#Move Datastores into Clusters
#for each row in CSV
foreach($line in $DatastoreLocations){
    #counter starts at 0 (the name of the Datastore Cluster)
    $y = 0
    #Set Datastore Cluster Name
    $ClusterName = $line.0
    #Increment $y until you reach a blank column in CSV
    DO{
      $y++
      }
    Until ($line.$y -like "")
    #Subtract 1 number from CSV to ensure you dont try adding a blank datastore
    $count = $y-1
    #set datastore name (anything after row 0)
    $datastore = $line.$count
    #add datastore until $count is equal to 0 (the name of the Datastore Cluster)
    DO{
    $datastore = $line.$count
    Move-Datastore -Datastore $datastore -Destination $ClusterName -WhatIf
    $count = $count-1
    }
    Until($count -eq 0)
    }



#Finally moves datastores to folder desintations, if not contained within a cluster
$allDatastores = import-clixml $directory\datastore-locations.xml
foreach ($thisDS in $allDatastores) {
if($thisDS.ParentFolder -notlike ""){get-datastore $thisDS.name | move-datastore -destination (get-folder $thisDS.ParentFolder) -WhatIf}
}#>