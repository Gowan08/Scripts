param
(
	[alias("d")]
	$Directory =  "Enter your Directory where you would like to dump configuration files",
    [alias("vc")]
	$vCenter = "Enter the vCenter of the VIServer you would like to export"
)

#Just incase you ran this from Powershell...
Add-PSSnapin VMWare* -ErrorAction SilentlyContinue

#Change Warning preference to make the script pretty..
$WarningPreference = "SilentlyContinue"

#Clearscreen..
cls

#Convert to Upper
$vCenter = $vcenter.ToUpper()

#Connect to the VI Server specified..
Try{
Write-Host "Connecting to Source vCenter" -ForegroundColor Yellow
Connect-VIServer -Server $vCenter -WarningAction SilentlyContinue
}
Catch{
Write-Host "Connection to Source vCenter failed, most likely due to a network error or incorrect credentials, please re-run the script with the correct parameters and try again" -ForegroundColor Red
exit
}

#Connected Information
cls
Write-host "Successfully Connected to $vCenter, moving forward with Foundation Capture" -ForegroundColor Green
Write-host "=========================================================================="
#Trim and set target directory for where the exported files exist
$directory = $directory.trim("\")

#Create specific Dirs that may later be changed in the script
$vCenterDir = "$directory\$vCenter"
$GlobalDir = "$vCenterDir\GlobalSettings\"

#Create vCenter Directory Preemptively
new-item $vCenterDir -type directory -erroraction SilentlyContinue | Out-Null

#Import special functions Provided by VMWare..
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

#Import Modules required for this script to be fully successful
Write-Host "Importing All Required Modules for Script"
Write-Host ""

Try{
import-module DRSRule
}
Catch{
    if(Get-Module -Name DRSRule){
        Write-Host "DRSRule already imported"
        Write-Host ""
    }
    Else{
    Write-Host "Copying DRSRule to your Users's Profile Path, and unblocking"
    Write-Host ""
    $dependencydirectory = "$PSScriptRoot\Dependencies"
    $modulepath = Join-Path ${env:\userprofile} "Documents\WindowsPowerShell\Modules"
    new-item $modulepath\DRSRule -type directory -erroraction SilentlyContinue | Out-Null
    Copy-Item $dependencydirectory\DRSRule-Latest\* -Destination $modulepath\DRSRule
    Get-ChildItem $modulepath\DRSRule | Unblock-File
    import-module DRSRule
    }
}
#create golobal dir
new-item $GlobalDir -type directory -erroraction SilentlyContinue | Out-Null

#Get-VIRoles
get-virole | where {$_.issystem -eq $false} | export-clixml $GlobalDir\roles.xml

#Get VI Permissions
Get-VIPermission | export-clixml $GlobalDir\permissions.xml

#Get All Datacenters
$datacenter = Get-Datacenter

foreach($dc in $datacenter){
#Directory magic to created layered folder structure
$directory =  "$vCenterDir\$dc"

#Create Root Directory If not created
new-item $directory -type directory -erroraction SilentlyContinue | Out-Null

#Change Capture Type to "Storage"
$CaptureType = "Storage"
#Reset $directory to Subfolder \Storage
$subdir = "$directory\$CaptureType"
#Create Directory If not created
new-item $subdir -type directory -erroraction SilentlyContinue | Out-Null

#Start Storage Configuration Capture
Write-Host "Gathering all foundational Storage information from $vCenter"

#Get all Datastore clusters
$StorageDRS = $dc | Get-DatastoreCluster

#Get all Datastores
$Datastores = $dc | Get-Datastore

#Place all storage folders into $folders variable
$folders = $dc | Get-Folder | where {$_.Type -eq "datastore"}

#get the root Storage Folder
$rootStorageFolder = $dc | Get-Folder | where {$_.type -eq "datastore" -and $_.Parent.Name -eq $dc.Name}

#get the end storage folders (folders with no children folders)
$endfolders = $dc | Get-Folder | where {$_.extensiondata.ChildEntity.Type -notcontains "Folder" -and $_.Type -eq "datastore"}

#get directory chain for each end folder and output to CSV
foreach($endfolder in $endfolders){
$findFolderParent = $endfolder.Parent
    foreach($folder in $folders){
    $DatastoreFolderLocation = @()
        IF($folder -eq $findFolderParent){
            $DatastoreFolderLocation += $endfolder.Name
            IF($folder -ne $rootStorageFolder){
            DO {
                $DatastoreFolderLocation += $folder.Name
                $folder = $folder.Parent
                }
            Until($folder -eq $rootStorageFolder)
            }
            $DatastoreFolderLocation += $folder.Name
            $DatastoreFolderLocation -join "," >>$subdir\StorageFolderLocations.csv        
        }
    }
}

#Find each Datastore Cluster's Parent, get folder structure, output to StorageClusterLocations.csv. Gather All Hosts attached to Clusters, output to ClusterDatastoreLocations.csv
#Gather all Storage Cluster Settings, output to StorageClusterSettings.csv. Also Export Default VM affinity toStorageClusterVMAffinity.csv.
foreach($SCluster in $StorageDRS){
$findClusterid = $SCluster.Id
    foreach($folder in $folders){
    $DatastoreClusterLocation = @()
        IF($folder.ExtensionData.ChildEntity -match $findClusterid){
            $DatastoreClusterLocation += $SCluster.Name
            IF($folder.Name -ne $rootStorageFolder){
            DO {
                $DatastoreClusterLocation += $folder.Name
                $folder = $folder.Parent
                }
            Until($folder.name -eq "datastore")
            }
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
$findDatastoreid = $Datastore.Id
    foreach($folder in $folders){
    $DatastoreLocation = @()
        IF($folder.ExtensionData.ChildEntity -match $findDatastoreid){
            $DatastoreLocation += $Datastore.Name
            IF($folder.Name -ne $rootStorageFolder){
            DO {
                $DatastoreLocation += $folder.Name
                $folder = $folder.Parent
                }
            Until($folder.Name -eq "datastore")
            }
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

#Place all host and cluster folders into $folders variable
$folders = $dc | Get-Folder | where {$_.Type -eq "HostAndCluster"}

#get the root Host and cluster Folder
$rootHostandClusterFolder = $dc | Get-Folder | where {$_.type -eq "HostAndCluster" -and $_.Parent.Name -eq $dc.Name}

#get the end storage folders (folders with no children folders)
$endfolders = $dc | Get-Folder | where {$_.extensiondata.ChildEntity.Type -notcontains "Folder" -and $_.Type -eq "HostandCluster"}

#get directory chain for each end folder and output to CSV
foreach($endfolder in $endfolders){
$findFolderParent = $endfolder.Parent
    foreach($folder in $folders){
    $HostClusterFolderLocation = @()
        IF($folder -eq $findFolderParent){
            $HostClusterFolderLocation += $endfolder.Name
            IF($folder -ne $rootHostandClusterFolder){
            DO {
                $HostClusterFolderLocation += $folder.Name
                $folder = $folder.Parent
                }
            Until($folder -eq $rootHostandClusterFolder)
            }
            $HostClusterFolderLocation += $folder.Name
            $HostClusterFolderLocation -join "," >>$subdir\HostandClusterFolderLocations.csv   
        }
    }
}

#Find each Host Cluster's Parent, get folder structure, output to HostClusterLocations.csv. Gather All Hosts attached to Clusters, output to ClusterHostLocations.csv
#Gather all Cluster Settings, output to HostClusterSettings.csv. Also Export DRS rules to ClusterName-DRSRules.json File.
foreach($Cluster in $HostClusters){
$ClusterHParray = @()
$findClusterParent = $Cluster.ParentFolder
    foreach($folder in $folders){
    $HostClusterLocation = @()
        IF($folder -eq $findClusterParent){
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

#Get all Virtual Distributed Switches
$VDSwitches = $dc | Get-VDSwitch

#Get all Virtual Standard Switch Port Groups
$PortGroups = $dc | Get-VirtualPortGroup | Where {$_.ExtensionData.Key -notmatch "dvportgroup" -and $_.Port -eq $null} | Get-Unique

#Place all network folders into $folders variable
$folders = $dc | Get-Folder | where {$_.Type -eq "Network"}

#get the root Networking Folder
$rootNetworkFolder = $dc | Get-Folder | where {$_.type -eq "Network" -and $_.Parent.Name -eq $dc.Name}

#get the end storage folders (folders with no children folders)
$endfolders = $dc | Get-Folder | where {$_.extensiondata.ChildEntity.Type -notcontains "Folder" -and $_.Type -eq "network"}

#get directory chain for each end folder and output to CSV
foreach($endfolder in $endfolders){
$findFolderParent = $endfolder.Parent
    foreach($folder in $folders){
    $NetworkFolderLocation = @()
        IF($folder -eq $findFolderParent){
            $NetworkFolderLocation += $endfolder.Name
            IF($folder -ne $rootNetworkFolder){
            DO {
                $NetworkFolderLocation += $folder.Name
                $folder = $folder.Parent
                }
            Until($folder -eq $rootNetworkFolder)
            }
            $NetworkFolderLocation += $folder.Name
            $NetworkFolderLocation -join "," >>$subdir\NetworkFolderLocations.csv        
        }
    }
}

#Find each DVS's Parent, get folder structure, output to DVSLocations.csv. Also Export Switch Configuration.
foreach ($VDSwitch in $VDSwitches){
    $findVDSid = $VDSwitch.Id
    $ExportFile = "$VDSwitch-Export.zip"
    foreach($folder in $folders){
    $VDSLocation = @()
        If($folder.ExtensionData.ChildEntity -match $findVDSid){
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

#Get all Virtual Machines
$AllVMs = $dc | Get-VM

#list of all vAPP VMs
$vAppVMs = $dc | get-vapp | get-VM

#Get all Templates
$AllTemplates = $dc | Get-Template

#Get all vApps
$AllvApps = $dc | Get-vApp

#Place all VM folders into $folders variable
$folders = $dc | Get-Folder | where {$_.Type -eq "VM"}

#get the root VM Folder
$rootVMFolder = $dc | Get-Folder | where {$_.type -eq "VM" -and $_.Parent.Name -eq $dc.Name}

#get the end storage folders (folders with no children folders)
$endfolders = $dc | Get-Folder | where {$_.extensiondata.ChildEntity.Type -notcontains "Folder" -and $_.Type -eq "VM"}

#get directory chain for each end folder and output to CSV
foreach($endfolder in $endfolders){
$findFolderParent = $endfolder.Parent
    foreach($folder in $folders){
    $VMFolderLocation = @()
        IF($folder -eq $findFolderParent){
            $VMFolderLocation += $endfolder.Name
            IF($folder -ne $rootVMFolder){
            DO {
                $VMFolderLocation += $folder.Name
                $folder = $folder.Parent
                }
            Until($folder -eq $rootVMFolder)
            }
            $VMFolderLocation += $folder.Name
            $VMFolderLocation -join "," >>$subdir\VMFolderLocations.csv        
        }
    }
}

#Find each VM's Parent, get folder structure, output to VMLocations.csv.
foreach ($VM in $AllVMs){
    IF($vAPPVMs -notcontains $VM){
    $findVMid = $VM.id
    foreach($folder in $folders){
    $VMLocation = @()
        If($folder.ExtensionData.ChildEntity -match $FindVMid){
            $VMLocation += $VM.Name
            If($folder.id -ne $rootVMFolder.id){
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
}
#Find each Template's Parent, get folder structure, output to TemplateLocations.csv.
foreach ($Template in $AllTemplates){
    $findTemplateid = $Template.id
    foreach($folder in $folders){
    $TemplateLocation = @()
        If($folder.ExtensionData.ChildEntity -match $FindTemplateid){
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
    $findvAppid = $vApp.Id
    foreach($folder in $folders){
    $vAppLocation = @()
        If($folder.ExtensionData.ChildEntity -match $FindvAppid){
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

#Export Annotations
Write-Host "Exporting all Annotations"
Get-VM | ForEach-Object {
$VM = $_
$VM | Get-Annotation |`
ForEach-Object {
$Report = "" | Select-Object VM,Name,Value
$Report.VM = $VM.Name
$Report.Name = $_.Name
$Report.Value = $_.Value
$Report
}
} | Export-Csv -Path $subdir\Migration-VMAnnotations.csv -NoTypeInformation

}

#Ask if you want to pre-popluate VSS and PortGroups

Write-Host "Do you want to pre-generate all Virtual Standard Switches and Pre-populate the PortGroups to migrate VMs to?" -ForegroundColor Green
$MakeVSS = Read-Host "enter Yes or No"
If($MakeVSS -like "y*" -or $MakeVSS -like "Y*"){
Write-Host "Gathering Port Groups attached to each dvSwitch and creating a replica vSwitch with -VSS appended to each portgroup" -ForegroundColor Green

#Copies all Port Groups from a Distributed vSwitch to a Standard vSwitch
#Orginal Author: Jason Coleman (virtuallyjason.blogspot.com)
#Usage: Make-VSS.ps1 -h [the target ESXi host to get the new standard switch, must have access to the DVS] -s [the name of the DVS to copy] -d [the name of the VSS to copy the Port Groups to]

$VMHosts = Get-VMHost | where {$_.Name -eq "prd1-4-vr4c4a10.accounts.cdcr.ca.gov"}

foreach($VMHost in $VMHosts){
    $VDSs = Get-VMHost $VMhost | Get-VDSwitch
    foreach($VDS in $VDSs){
        $vss = $VDS.Name
        IF(!(Get-VirtualSwitch -VMHost $VMHost -Name $vss -Standard -ErrorAction SilentlyContinue)){
        New-VirtualSwitch  -VMHost $VMHost -Name $vss -ErrorAction SilentlyContinue
        #Create an empty array to store the port group translations
        $pgTranslations = @()
        #Get the destination vSwitch
        $destSwitch = Get-VirtualSwitch -host $VMHost -name $vss -Standard
        #Get a list of all port groups on the source distributed vSwitch
        $allPGs = get-vdswitch -name $VDS | get-vdportgroup
        foreach ($thisPG in $allPGs)
        {
            $thisObj = new-object -Type PSObject
            $thisObj | add-member -MemberType NoteProperty -Name "dVSPG" -Value $thisPG.Name
            $thisObj | add-member -MemberType NoteProperty -Name "VSSPG" -Value "$($thisPG.Name)-VSS"
            $thisObj | Add-Member -MemberType NoteProperty -Name "Host" -Value $VMHost.Name
            new-virtualportgroup -virtualswitch $destSwitch -name "$($thisPG.Name)-VSS"
            # Ensure that we don't try to tag an untagged VLAN
            if ($thisPG.vlanconfiguration.vlanid)
            {
	            get-virtualportgroup -virtualswitch $destSwitch -name "$($thisPG.Name)-VSS" | Set-VirtualPortGroup -vlanid $thisPG.vlanconfiguration.vlanid
            }
            $pgTranslations += $thisObj
        } 
        }
        Else{
        Write-Host "Somehow, a standard vSwitch named $vss already existed with the exact same name, what are the odds! Not continuing forward on $VMHost." -ForegroundColor Yellow
        }
    }
    $pgTranslations | export-clixml "$GlobalDir\$vCenter-PGTranslations.xml"
}
}
Else{
Write-Host "Not performing dvSwitch capture or creating a replica vSwitch with -VSS appended to each portgroup. you must perfrom this step manually with the Make-VSS script before moving forward." -ForegroundColor Yellow
}
Write-Host "Please make note of the following directory so that you may run the Set-vCenterFoundation.ps1. When you do run it, enter the following as parameters:"  -ForegroundColor Green
Write-Host "Directory = $vCenterDir" -ForegroundColor Cyan