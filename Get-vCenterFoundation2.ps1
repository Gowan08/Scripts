param
(
	[alias("d")]
	$Directory =  "Enter your Directory where you would like to dump files",
	[alias("dc")]
	$Datacenter = "Enter the Datacenter of the VIServer you would like to export",
    [alias("vc")]
	$vCenter = "Enter the vCenter of the VIServer you would like to export"
)

$Directory = "C:\utils\migration"
$datacenter = "VDC"
$vCenter = "VDCVCENTER"

#Trim and set target directory for where the exported files exist
$directory = $directory.trim("\")

#Import special function Provided by VMWare..
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

#Directory magic to created layered folder structure
$directory =  "$directory\$vCenter\$datacenter"

#Create Root Directory If not created
new-item $directory -type directory -erroraction SilentlyContinue | Out-Null

#Get Datacenter
$dc = get-datacenter $datacenter

#Change Capture Type to "Storage"
$CaptureType = "Storage"
#Reset $directory to Subfolder \Storage
$subdir = "$directory\$CaptureType"
#Create Directory If not created
new-item $subdir -type directory -erroraction SilentlyContinue | Out-Null

#Start Storage Configuration Capture
cls
Write-Host "Gathering all foundational Storage information from $vCenter"

#Get all Datastore clusters
$StorageDRS = $dc | Get-DatastoreCluster

#Get all Datastores
$Datastores = $dc | Get-Datastore

#Export all Storage Folders in XML
$dc | get-folder | where {$_.type -eq "datastore"} | select name,parent | export-clixml $subdir\Storagefolders.xml

#Place all storage folders into $folders variable
$folders = Get-Folder | where {$_.Type -eq "datastore"}

#get the root storage Folder
$rootStorageFolder = Get-Folder | where {$_.type -eq "datastore" -and $_.Parent.Name -eq $dc.Name}

#Find each Datastore Cluster's Parent, get folder structure, output to StorageClusterLocations.csv. Gather All Hosts attached to Clusters, output to ClusterDatastoreLocations.csv
#Gather all Storage Cluster Settings, output to StorageClusterSettings.csv. Also Export Default VM affinity toStorageClusterVMAffinity.csv.
foreach($SCluster in $StorageDRS){
$findClusterParent = $SCluster.ExtensionData.Parent.value
    foreach($folder in $folders){
    $DatastoreClusterLocation = @()
        IF($folder.Id -match $findClusterParent){
            $DatastoreClusterLocation += $SCluster.Name
            DO {
                $DatastoreClusterLocation += $folder.Name
                IF($folder.Name -ne $rootStorageFolder){
                $folder = $folder.Parent
                }
                }
            Until($folder.name -eq "datastore")
            $DatastoreClusterLocation += $folder.Name
            $DatastoreClusterLocation -join "," >>$subdir\StorageClusterLocations.csv        
        }
    }
$SCluster | select Name,IOLatencyThresholdMillisecond,IOLoadBalanceEnabled,SdrsAutomationLevel,SpaceUtilizationThresholdPercent | Export-Csv -Path $subdir\StorageClusterSettings.csv -NoTypeInformation -Append
$ClusterDatastoreLocations = @()
$Clusterdatastores = $SCluster | Get-Datastore
$ClusterDatastoreLocations += $SCluster.Name
$ClusterDatastoreLocations += $Clusterdatastores.Name
$ClusterDatastoreLocations -join "," >>$subdir\ClusterDatastoreLocations.csv
Get-DatastoreCluster | Select Name, @{N="DefaultIntraVmAffinity";E={($_ | Get-View).PodStorageDRSEntry.StorageDRSConfig.PodConfig.DefaultIntraVmAffinity}} | Export-CSV -Path $subdir\StorageClusterVMAffinity.csv -NoTypeInformation
}

#get all datastore locations
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
                }
            Until($folder.Name -eq "datastore")
            $DatastoreLocation += $rootStorageFolder
            $DatastoreLocation -join "," >>$subdir\DatastoreLocations.csv          
        }
    }
}

#Change Capture Type to "HostandClusters"
$CaptureType = "HostandClusters"
#Reset $directory to Subfolder \HostandClusters
$subdir = "$directory\$CaptureType"
#Create Directory If not created
new-item $subdir -type directory -erroraction silentlycontinue | Out-Null

#Start Host and Cluster Configuration Capture
Write-Host "Gathering all foundational Host and Cluster information from $vCenter"

#Get all host clusters
$HostClusters = $dc | Get-Cluster

#Get all hosts
$Hosts = $dc | Get-VMHost

#Get all host Profiles
$GetHP = Get-VMHostProfile

#Export all Host and Cluster Folders in XML
$dc | get-folder | where {$_.type -eq "HostAndCluster"} | select name,parent | export-clixml $subdir\HostandClusterfolders.xml

#Place all host and cluster folders into $folders variable
$folders = Get-Folder | where {$_.Type -eq "HostAndCluster"}

#get the root Host and cluster Folder
$rootHostandClusterFolder = Get-Folder | where {$_.type -eq "HostAndCluster" -and $_.Parent.Name -eq $dc.Name}

#Find each Host Cluster's Parent, get folder structure, output to HostClusterLocations.csv. Gather All Hosts attached to Clusters, output to ClusterHostLocations.csv
#Gather all Cluster Settings, output to HostClusterSettings.csv. Also Export DRS rules to ClusterName-DRSRules.json File.
foreach($Cluster in $HostClusters){
$ClusterHParray = @()
$findClusterParent = $Cluster.ParentId
    foreach($folder in $folders){
    $HostClusterLocation = @()
        IF($folder.Id -match $findClusterParent){
            $HostClusterLocation += $Cluster.Name
            IF($folder.Name -ne $rootHostandClusterFolder){
                DO {
                $HostClusterLocation += $folder.Name
                $folder = $folder.Parent
                }
                Until($folder.name -eq "host")
            }
            $HostClusterLocation += $folder.Name
            $HostClusterLocation -join "," >>$subdir\HostClusterLocations.csv          
        }
    }
$Cluster | Select * | Export-Csv -Path $subdir\HostClusterSettings.csv -Append -NoTypeInformation
#Get Cluster Host Profile
$ClusterHP = Get-Cluster -name $Cluster.Name | Get-VMHostProfile
$ClusterHParray += $ClusterHP.Name
$ClusterHParray += $Cluster.Name
$ClusterHParray -join "," >>$subdir\ClusterHostProfiles.csv
#Get hosts in cluster
$ClusterHostLocations = @()
$ClusterHosts = $Cluster | Get-VMHost
$ClusterHostLocations += $Cluster.Name
$ClusterHostLocations += $ClusterHosts.Name
$ClusterHostLocations -join "," >>$subdir\ClusterHostLocations.csv

#If you dont have Export-DRSRUle...you must get the module unblocked and installed.
$Cluster | Export-DRSRule -Path "$subdir\$Cluster-DRSRules.json" | Out-Null
}

#Get all Host locations if outside a cluster, output to HostLocations.csv
foreach($VMHost in $Hosts){
$HostHParray = @()
$findHostParent = $VMHost.Parent
    foreach($folder in $folders){
    $HostLocation = @()
        IF($folder -eq $findHostParent){
            $HostLocation += $VMHost.Name
            IF($folder.Name -ne $rootHostandClusterFolder){
            DO {
                $HostLocation += $folder.Name
                $folder = $folder.Parent
                }
            Until($folder.Name -eq "host")
            }
            $HostLocation += $folder.Name
            $HostLocation -join "," >>$subdir\HostLocations.csv
        }
    }
$HostHP = Get-VMHost -name $VMhost.Name | Get-VMHostProfile
$HostHParray += $HostHP.Name
$HostHParray += $VMHost.Name
$HostHParray -join "," >>$subdir\HostHostProfiles.csv
}

Foreach ($HP in $GetHP){
Export-VMHostProfile -FilePath "$subdir\$HP-HostProfile.prf" -Profile $HP | Out-Null
}

#Change Capture Type to "Network"
$CaptureType = "Network"
#Reset $directory to Subfolder \Network
$subdir = "$directory\$CaptureType"
#Create Directory If not created
new-item $subdir -type directory -erroraction silentlycontinue | Out-Null

#Start Networking Configuration Capture
Write-Host "Gathering all foundational Network information from $vCenter"

#Export all Networking Folders in XML
$dc | get-folder | where {$_.type -eq "Network"} | select name,parent | export-clixml $subdir\Networkfolders.xml

#Get all Virtual Distributed Switches
$VDSwitches = $dc | Get-VDSwitch

#Get all Virtual Standard Switch Port Groups
$PortGroups = $dc | Get-VirtualPortGroup | Where {$_.ExtensionData.Key -notmatch "dvportgroup" -and $_.Port -eq $null} | Get-Unique

#Place all network folders into $folders variable
$folders = Get-Folder | where {$_.Type -eq "Network"}

#get the root Networking Folder
$rootNetworkFolder = Get-Folder | where {$_.type -eq "Network" -and $_.Parent.Name -eq $dc.Name}

#Find each DVS's Parent, get folder structure, output to DVSLocations.csv. Also Export Switch Configuration.
foreach ($VDSwitch in $VDSwitches){
    $findVDSParent = $VDSwitch.ExtensionData.Parent
    $ExportFile = "$VDSwitch-Export.zip"
    foreach($folder in $folders){
    $VDSLocation = @()
        If($folder.Id -match $findVDSParent){
            $VDSLocation += $VDSwitch.Name
            If($folder.Name -ne $rootNetworkFolder){
                DO {
                    $VDSLocation += $folder.Name
                    $folder = $folder.Parent
                    }
                Until($folder.name -eq "network")
            }
            $VDSLocation += $folder.Name
            $VDSLocation -join "," >>$subdir\DVSLocations.csv          
        }
    }
$VDSwitch | Export-VDSwitch -Destination "$subdir\$ExportFile" | Out-Null
}

#Get Parent and folder structure housing Port Groups
foreach ($PortGroup in $PortGroups){
$PortGroupView = get-view -ViewType Network -Filter @{“Name”=$PortGroup.name}
$PortGroupParent = $PortGroupView.Parent
    Foreach($folder in $Folders){
        $PortGroupFolderLocation = @()
                If($PortGroupParent -eq $folder.ExtensionData.moref){
                    $PortGroupFolderLocation += $PortGroup.Name
                        If($Folder.Name -ne $rootNetworkFolder){
                            DO {
                                $PortGroupFolderLocation += $Folder.Name
                                $folder = $folder.Parent
                                }
                            Until($folder.name -eq "network")
                        }
                    $PortGroupFolderLocation += $Folder.Name
                    $PortGroupFolderLocation -join "," >>$subdir\PortGroupLocations.csv
                }   
    }
}

#Change Capture Type to "VM"
$CaptureType = "VM"
#Reset $directory to Subfolder \VM
$subdir = "$directory\$CaptureType"
#Create Directory If not created
new-item $subdir -type directory -erroraction silentlycontinue | Out-Null

#Start VM Configuration Capture
Write-Host "Gathering all foundational VM information from $vCenter"

#Export all VM Folders in XML
$dc | get-folder | where {$_.type -eq "VM"} | select name,parent | export-clixml $subdir\VMfolders.xml

#Get all Virtual Machines
$AllVMs = $dc | Get-VM

#Get all Templates
$AllTemplates = $dc | Get-Template

#Get all vApps
$AllvApps = $dc | Get-vApp

#Place all VM folders into $folders variable
$folders = Get-Folder | where {$_.Type -eq "VM"}

#get the root VM Folder
$rootVMFolder = Get-Folder | where {$_.type -eq "VM" -and $_.Parent.Name -eq $dc.Name}

#Find each VM's Parent, get folder structure, output to VMLocations.csv.
foreach ($VM in $AllVMs){
    $findVMParent = $VM.ExtensionData.Parent
    foreach($folder in $folders){
    $VMLocation = @()
        If($folder.Id -match $findVMParent){
            $VMLocation += $VM.Name
            If($folder.Name -ne $rootVMFolder){
                DO {
                    $VMLocation += $folder.Name
                    $folder = $folder.Parent
                    }
                Until($folder.name -eq "vm")
            }
            $VMLocation += $folder.Name
            $VMLocation -join "," >>$subdir\VMLocations.csv
        }
    }
}
#Find each Template's Parent, get folder structure, output to TemplateLocations.csv.
foreach ($Template in $AllTemplates){
    $findTemplateParent = $Template.ExtensionData.Parent
    foreach($folder in $folders){
    $TemplateLocation = @()
        If($folder.Id -match $findTemplateParent){
            $TemplateLocation += $Template.Name
            If($folder.Name -ne $rootVMFolder){
                DO {
                    $TemplateLocation += $folder.Name
                    $folder = $folder.Parent
                    }
                Until($folder.name -eq "vm")
            }
            $TemplateLocation += $folder.Name
            $TemplateLocation -join "," >>$subdir\TemplateLocations.csv
        }
    }
}
#Find each vApp's Parent, get folder structure, output to vAppLocations.csv. WARN if there are vApps
foreach ($vApp in $AllvApps){
    $findvAppParent = $vApp.ExtensionData.ParentFolder
    foreach($folder in $folders){
    $vAppLocation = @()
        If($folder.Id -match $findvAppParent){
            $vAppLocation += $vApp.Name
            If($folder.Name -ne $rootVMFolder){
                DO {
                    $vAppLocation += $folder.Name
                    $folder = $folder.Parent
                    }
                Until($folder.name -eq "vm")
            }
            $vAppLocation += $folder.Name
            $vAppLocation -join "," >>$subdir\vAppLocations.csv
        }
    }
Write-Host "This utility does NOT export vApps, you must manually create the"$vApp.Name"vApp on the destination vCenter before running the Finalize command"
}


Write-Host "You now must run Set-vCenterFoundation.ps1. enter the following as parameters:
OldvCenter = $vCenter
OldDatacenter = $Datacenter
Directory = $directory

"