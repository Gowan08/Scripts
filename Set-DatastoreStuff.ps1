#Add-PSSnapin VMware*
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

#Create Folder Structure for Storage
#foreach ($thisFolder in (import-clixml $directory\Storagefolders.xml | where {!($_.name -eq "datastore")})) {(get-datacenter $datacenter) | get-folder $thisFolder.Parent | new-folder $thisFolder.Name -confirm:$false}
#Set Header to be 128...maximum of storage cluster
$header = 0..128
#Gather all csv's from Get-DatastoreStuff.ps1
$DSCLocation = "StorageClusterLocations.csv" 
$DSCConfig = "StorageClusterSettings.csv" 
$CDLocations = "ClusterDatastoreLocations.csv" 
$VMAffinity = "StorageClusterVMAffinity.csv" 
$FDLocations = "DatastoreLocations.csv"
#send all csv information to variables
$StorageClusterLocations = Import-CSV "$directory\$DSCLocation" -delimiter "," -header $header
$StorageCLusterSettings = Import-CSV "$directory\$DSCConfig"
$ClusterDatastoreLocations = Import-CSV "$directory\$CDLocations" -delimiter "," -header $header
$VMAffinitySettings = Import-CSV "$directory\$VMAffinity"
$FolderDatastoreLocations = Import-CSV "$directory\$FDLocations" -delimiter "," -header $header
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
    New-DatastoreCluster -Name $ClusterName -Location $root -WhatIf
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
        New-DatastoreCluster -Name $ClusterName -Location $folder -WhatIf
        }
    }
<#Set Datastore Cluster Captured Settings from CSV
foreach($setting in $StorageCLusterSettings){
$IOLBEnabled = [System.Convert]::ToBoolean($Setting.IOLoadBalanceEnabled)
Set-DatastoreCluster -DatastoreCluster $Setting.Name -IOLatencyThresholdMillisecond $Setting.IOLatencyThresholdMillisecond -IOLoadBalanceEnabled $IOLBEnabled -SdrsAutomationLevel $Setting.SdrsAutomationLevel -SpaceUtilizationThresholdPercent $Setting.SpaceUtilizationThresholdPercent -WhatIf
}
#Set Intra VM Affinity Settings within each DS Cluster from CSV Capture
 foreach($line in $VMAffinitySettings){
    if($line.DefaultIntraVmAffinity -eq "False"){
    Get-DatastoreCluster -Name $line.Name | Set-DatastoreClusterDefaultIntraVmAffinity 
    }
 }
#this lets you know what the setting is initally or after the fact, it was on the VMware Blog I grabed the function from, figured it should be included.
#Get-DatastoreCluster | Select Name, @{N="DefaultIntraVmAffinity";E={($_ | Get-View).PodStorageDRSEntry.StorageDRSConfig.PodConfig.DefaultIntraVmAffinity}}
#>

#Move Datastores into Datastore Clusters
#for each row in CSV
foreach($line in $ClusterDatastoreLocations){
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
    #Datastore at $count position
    $datastore = $line.$count
    #Gets moved into $ClusterName
    Move-Datastore -Datastore $datastore -Destination $ClusterName -WhatIf
    #Decrease count
    $count = $count-1
    }
    #until at position 0 ($ClusterName)
    Until($count -eq 0)
    }

#Move Datastores into Folders
#for each row in CSV
foreach($line in $FolderDatastoreLocations){
    #start $y counter at 1 because 0 is the Datastore
    $y = 1
    #set Datastore name to $line.0
    $DatastoreName = $line.0
    DO{
      #If $line.$y doesnt equal the word datastore, icrement and do this again.
      IF($line.$y -ne "datastore"){$y++}
      #If $line.$y equals the word datastore, you found the root.
      IF($line.1 -eq "datastore"){$y=0}
      }
    Until ($line.$y -match "datastore" -or $y -eq 0)
    #if outcome of above is $y = 0, you know the root, and proceed forward.
    If($y -eq 0){
    #set root to $line.1
    $root = $line.1
    #Run move command on Datastore to Root
    Move-Datastore -Datastore $DatastoreName -Destination $root -WhatIf
    }
    #otherwise, you found the root at a higher location..
    Else{
    #set count 1 back from the "blank" column in CSV, which would be the root.
    $count = $y-1
    #for all values inside $count
    foreach($value in $count){
        #set root to whatever $count (y-1) was
        $root = $line.$y
        #get the folder where the parent equals $root
        $folder = Get-Folder -Name $line.$count | where {$_.Parent.Name -eq $root} 
        DO{
        #If $folder doesnt equal the first folder found in the csv
        If($line.1 -ne $folder){
        #root now equals the folder (next level down)
        $root = $folder
        #decrease the $count value
        $count = $count - 1
        #get the next folder down
        $folder = Get-Folder -Name $line.$count | where {$_.Parent.Name -eq $root} 
        }
        }
        #until $line.1 and $folder are the same (the lowest level folder)
        Until($line.1 -eq $folder)
        }
        #Run move command on Datastore to lowest level folder
        Move-Datastore -Datastore $DatastoreName -Destination $folder -WhatIf
        }
}