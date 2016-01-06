param
(
	[alias("d")]
	$Directory =  "Enter your Directory where you would like to dump files",
	[alias("dc")]
	$Datacenter = "Enter the Datacenter of the VIServer you would like to export",
    [alias("vc")]
	$vCenter = "Enter the vCenter of the VIServer you would like to export",
    [alias("oldvc")]
	$OldvCenter = "Enter the previous vCenter where you exported from",
    [alias("olddc")]
	$OldDatacenter = "Enter the previous vCenter's Datacenter name where you exported from",
    [bool]$staging  = $true
)

    $Directory =  "C:\utils\Migration"
	$Datacenter = "VDC"
	$vCenter = "VDCVCMGMT1"
	$OldvCenter = "VDCVCENTER"
	$OldDatacenter = "VDC"
    [bool]$staging  = $true

switch($staging)
{
    $false {Write-Host "You are preforming migration of object into pre-populated Folders,Clusters,DVSwitches within this vCenter, if you have not pre-populated, the script will also pre-populate the vCenter Correctly" -ForegroundColor Red; break}
    default {Write-Host 'You are only pre-polulating the new vCenter with all captured Folders, Clusters, DVSwitches. This script will not move any objects into the created Folders, Clusters, DVSwitches. You must run the script with the "-staging $false" switch to move objects.' -ForegroundColor DarkGreen ; break}
}
<#
.\Set-vCenterFoundation1.1.ps1 -OldvCenter VDCVCENTER -OldDatacenter VDC -Directory C:\utils\migration\ -Datacenter VDC -vCenter VDCVCMGMT1
#>

$confirm = Read-Host "Are you sure you want to continue? (Yes/No)"
IF($confirm -like "n" -or $confirm -like "no")
{
    Write-Host "Please re-run the script with the desired switches" -ForegroundColor Yellow
    Write-Host "No Actions Taken" -ForegroundColor Yellow
    ;Break
}

#Trim user inputed directory for where the exported files exist
$directory = $directory.trim("\")

#Set the directory for where exports exist
$directory = "$directory\$OldvCenter\$OldDatacenter"

#get Date
$Date = get-date

#variable to dump log info into
$log = "$directory\Migration-log.txt"

$prepopulatecheck = $False
#Manipulate Log File
If($staging -eq $False){
    $getlog = Get-Content -Path $directory\Migration-log.txt
    If($getlog -match "Stage Only" -and $getlog -match "Target vCenter: $vCenter"){
        $prepopulatecheck = $true
        }
}
Else{
    Try{
        get-item -Path $directory\Migration-log.txt -ErrorAction SilentlyContinue | Out-Null
        }
        Catch{
        new-item -path $directory -Name Migration-log.txt -type "file"  | Out-Null
        }
        Add-Content -Path $directory\Migration-log.txt -Value "`nStage Only at: $Date Target vCenter: $vCenter"  | Out-Null
}

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

#Set Header to be 128...
$header = 0..128

#Change Application Type to "Network"
$ApplicationType = "Storage"

#Reset $directory to Subfolder \Storage
$subdir = "$directory\$ApplicationType"

#Gather all csv's from Get-DatastoreStuff.ps1
$DSCLocation = "StorageClusterLocations.csv" 
$DSCConfig = "StorageClusterSettings.csv" 
$CDLocations = "ClusterDatastoreLocations.csv" 
$VMAffinity = "StorageClusterVMAffinity.csv" 
$FDLocations = "DatastoreLocations.csv"

#send all csv information to variables
$StorageClusterLocations = Import-CSV "$subdir\$DSCLocation" -delimiter "," -header $header
$StorageCLusterSettings = Import-CSV "$subdir\$DSCConfig"
$ClusterDatastoreLocations = Import-CSV "$subdir\$CDLocations" -delimiter "," -header $header
$VMAffinitySettings = Import-CSV "$subdir\$VMAffinity"
$FolderDatastoreLocations = Import-CSV "$subdir\$FDLocations" -delimiter "," -header $header

#If staging switch is true, and no previous pre-populate occured
IF($staging -eq $True -and $prepopulatecheck -eq $false){

#Create Folder Structure for Storage
foreach ($thisFolder in (import-clixml $subdir\Storagefolders.xml | where {!($_.name -eq "datastore")})) {(get-datacenter $datacenter) | get-folder $thisFolder.Parent | new-folder $thisFolder.Name -confirm:$false -ErrorAction SilentlyContinue | Format-List |Out-File $log -Append}

#Create Storage Clusters through a means of complicated methods..done to ensure the right folder is selected, and not in another directory with the same name on accident.
foreach($line in $StorageClusterLocations){
    $y = 1
    $SClusterName = $line.0
    DO{
        IF($line.$y -ne "datastore"){$y++}
        IF($line.1 -eq "datastore"){$y=0}
    }
    Until ($line.$y -eq "datastore" -or $y -eq 0)
    If($y -eq 0){
    $rootname = $line.1
    $root = get-folder | where {$_.Name -eq $rootname}
    New-DatastoreCluster -Name $SClusterName -Location $root | format-list | Out-File $log -Append
    }
    Else{
    $count = $y-1
    $rootname = $line.$y
    $root = get-folder | where {$_.Name -eq $rootname}
    $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
        If($subroot.Name -ne $line.1){
            DO{
            $count--
            $root = $subroot
            $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            }
            Until($line.1 -eq $Subroot.name)
        }
    New-DatastoreCluster -Name $SClusterName -Location $subroot | format-list | Out-File $log -Append
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
#this lets you know what the setting is initally or after the fact, it was on the VMware Blog I grabed the function from, figured it should be included.
#Get-DatastoreCluster | Select Name, @{N="DefaultIntraVmAffinity";E={($_ | Get-View).PodStorageDRSEntry.StorageDRSConfig.PodConfig.DefaultIntraVmAffinity}}
#
}

#End of Staging, Begining of move processes, all object must reside in target for this to function!
IF($staging -eq $False -and $prepopulatecheck -eq $True){
#Move Datastore Into Datastore Clusters
    foreach($line in $ClusterDatastoreLocations){
        $y = 0
        $SClusterName = $line.0
        DO{
          $y++
          }
        Until ($line.$y -like "")
        $count = $y-1
        $datastore = $line.$count
        DO{
        $datastore = $line.$count
        Move-Datastore -Datastore $datastore -Destination $SClusterName | format-list | Out-File $log -Append
        $count = $count-1
        }
        Until($count -eq 0)
    }
#Move Datastores into Folders
    foreach($line in $FolderDatastoreLocations){
        $y = 1
        $DatastoreName = $line.0
        DO{
          IF($line.$y -ne "datastore"){$y++}
          IF($line.1 -eq "datastore"){$y=0}
          }
        Until ($line.$y -eq "datastore" -or $y -eq 0)
        If($y -eq 0){
        $rootname = $line.1
        $root = get-folder | where {$_.Name -eq $rootname}
        Move-Datastore -Datastore $DatastoreName -Destination $root | format-list | Out-File $log -Append
        }
        Else{
        $count = $y-1
        $rootname = $line.$y
        $root = get-folder | where {$_.Name -eq $rootname}
        $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            If($subroot.Name -ne $line.1){
                DO{
                $count--
                $root = $subroot
                $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
                }
                Until($line.1 -eq $Subroot.name)
        Move-Datastore -Datastore $DatastoreName -Destination $subroot | format-list | Out-File $log -Append
            } 
        }
    }
}
#End Datastore/Datastore Cluster Scripts

#Change Application Type to "HostandClusters"
$ApplicationType = "HostandClusters"

#Reset $subdir to Subfolder \HostsandClusters
$subdir = "$directory\$ApplicationType"

#Gather all csv's from Get-DatastoreStuff.ps1
$HCLocation = "HostClusterLocations.csv" 
$HCConfig = "HostClusterSettings.csv" 
$CHLocations = "ClusterHostLocations.csv" 
$FHLocations = "HostLocations.csv"
$CHPLocations ="ClusterHostProfiles.csv"
$HHPLocations ="HostHostProfiles.csv"

#send all csv information to variables
$HostClusterSettings = Import-CSV "$subdir\$HCConfig"
$HostClusterLocations = Import-CSV "$subdir\$HCLocation" -delimiter "," -header $header
$ClusterHostLocations = Import-CSV "$subdir\$CHLocations" -delimiter "," -header $header
$HostHostProfiles = Import-CSV "$subdir\$HHPLocations" -delimiter "," -header $header
$ClusterHostProfiles = Import-CSV "$subdir\$CHPLocations" -delimiter "," -header $header
$FolderHostLocations = Import-CSV "$subdir\$FHLocations" -delimiter "," -header $header

#If staging switch is true, and no previous pre-populate occured
IF($staging -eq $True -and $prepopulatecheck -eq $false){

#Create Folder Structure in new vCenter
foreach ($thisFolder in (import-clixml $subdir\HostandClusterfolders.xml | where {!($_.name -eq "HostandCluster") -and $_.name -ne "host"})) {(get-datacenter $datacenter) | get-folder $thisFolder.Parent | where {$_.Type -eq "HostandCluster"} | new-folder $thisFolder.Name -confirm:$false  -ErrorAction SilentlyContinue}

#Create Storage Clusters through a means of complicated methods..done to ensure the right folder is selected, and not in another directory with the same name on accident.
foreach($line in $HostClusterLocations){
    $y = 1
    $ClusterName = $line.0
    DO{
      IF($line.$y -notMatch "host"){$y++}
      IF($line.1 -match "host"){$y=0}
      }
    Until ($line.$y -match "host" -or $y -eq 0)
    If($y -eq 0){
    $rootname = $line.1
    $root = get-folder | where {$_.Name -eq $rootname}
    New-Cluster -Name $ClusterName -Location $root 
    }
    Else{
    $count = $y-1
    $rootname = $line.$y
    $root = get-folder | where {$_.Name -eq $rootname}
    $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
        If($subroot.Name -ne $line.1){
            DO{
            $count--
            $root = $subroot
            $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            }
            Until($line.1 -eq $Subroot.name)
    New-Cluster -Name $ClusterName -Location $subroot 
        }
    }
}

#create inclusion list of items you CAN set on a cluster...some you just cant :(
$ParamList = @()
$ParamList = "DrsAutomationLevel","DrsEnabled","DrsMode","HAAdmissionControlEnabled","HAEnabled","HAIsolationResponse","HARestartPriority","VMSwapfilePolicy"
$NotAppliedParam = "HAFailoverLevel"

#Set Cluster Captured Settings from CSV
foreach($Cluster in $HostCLusterSettings){
    $SetClusterParams = @{ErrorAction = "Stop"}
    $ClusterName = $Cluster.Name
    $Cluster | Foreach-Object {
    foreach ($property in $_.PSObject.Properties)
    {
        If ($Property.Name -eq "HAFailoverLevel" -and $property.Value -eq 0){
            Write-Host "Warning: In order to Migrate to a 6.0 Environment, HA failover mode had to be set to greater then 1 Host, Please change "$Property.Name" setting after the fact, it was orginally "$Property.Value}
        foreach ($param in $ParamList){
        IF($Property.Name -eq $Param){
            If ($Property.Value -eq "True" -or $Property.Value -eq "False"){
                $value = [System.Convert]::ToBoolean($Property.Value)
                $SetCLusterParams.$param = $Value
                }
            Else{    
                $SetCLusterParams.$param = $Property.Value
                }
        }
        }
    }
    }
Set-Cluster -Cluster $ClusterName @SetCLusterParams -Confirm:$false
}
}

#End of Staging, Begining of move processes, all object must reside in target for this to function!
IF($staging -eq $False -and $prepopulatecheck -eq $True){

#Import DRS Rules once VMs and Hosts exist in Clusters
    foreach($Cluster in $HostCLusterSettings){
    Import-DrsRule -Path "$subdir\$ClusterName-DRSRules.json" -Cluster $ClusterName
    }

#Move Hosts into Host Clusters
    foreach($line in $ClusterHostLocations){
        $y = 0
        $ClusterName = $line.0
        DO{
          $y++
          }
        Until ($line.$y -like "")
        $count = $y-1
        $VMhost = $line.$count
        DO{
        $VMhost = $line.$count
        Move-VMHost -VMHost $VMhost -Destination $ClusterName 
        $count = $count-1
        }
        Until($count -eq 0)
    }

#Move Hosts into Folders
    $StandaloneHostProfileApply = @()
    foreach($line in $FolderHostLocations){
        $y = 1
        $VMHost = $line.0
        DO{
          IF($line.$y -ne "host"){$y++}
          IF($line.1 -eq "host"){$y=0}
          }
        Until ($line.$y -eq "host" -or $y -eq 0)
        If($y -eq 0){
        $rootname = $line.1
        $root = get-folder | where {$_.Name -eq $rootname}
        Move-VMHost -VMHost $VMhost -Destination $root 
        }
        Else{
        $count = $y-1
        $rootname = $line.$y
        $root = get-folder | where {$_.Name -eq $rootname}
        $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            If($subroot.Name -ne $line.1){
                DO{
                $count--
                $root = $subroot
                $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
                }
                Until($line.1 -eq $Subroot.name)
        Move-VMHost -VMHost $VMhost -Destination $subroot 
            }
        }
    $StandaloneHostProfileApply += $VMHost
    }

#Import all Host Profiles from Export...Getting only unique Host Profiles
    $HostProfileArray = @()
    Foreach($line in $HostHostProfiles){
    #Set Host Profile Name
    $HPName = $line.0
    $RefHost = $line.1
        If($HostProfileArray -notcontains $HPName){
        Import-VMHostProfile -FilePath "$subdir\$HPName-HostProfile.prf" -Name $HPName -ReferenceHost $RefHost
        $HostProfileArray += $HPName
        }
    }

#For every host profile, apply many numbers of clusters
    Foreach($line in $ClusterHostProfiles){
        $y = 0
        $HPName = $line.0
        DO{
          $y++
          }
        Until ($line.$y -like "")
        $count = $y-1
        $Cluster = $line.$count
        DO{
        $Cluster = $line.$count
        Apply-VMHostProfile -Entity $Cluster -Profile $HPName -AssociateOnly 
        $count = $count-1
        }
        Until($count -eq 0)
    }

#For every host found not in a cluster, apply a host profile
    Foreach($VMHost in $StandaloneHostProfileApply){
        Foreach($line in $HostHostProfiles){
            If($VMHost -match $line.1){
                $Profile = $line.0
            }
        }
    Apply-VMHostProfile -Entity $VMHost -Profile $Profile -AssociateOnly 
    }
}
#End of Host and Cluster Scripts

#Change Application Type to "Network"
$ApplicationType = "Network"

#Reset $directory to Subfolder \Network
$subdir = "$directory\$ApplicationType"

#Gather all csv's from Network Capture
$DVSLocation = "DVSLocations.csv" 
$PGLocations = "PortGroupLocations.csv" 

#send all csv information to variables
$DVSLocations = Import-CSV "$subdir\$DVSLocation" -delimiter "," -header $header
$PortGroupLocations = Import-CSV "$subdir\$PGLocations" -delimiter "," -header $header

#If staging switch is true, and no previous pre-populate occured
IF($staging -eq $True -and $prepopulatecheck -eq $false){

#Create Folder Structure in new vCenter
foreach ($thisFolder in (import-clixml $subdir\Networkfolders.xml | where {!($_.name -eq "Network")})) {(get-datacenter $datacenter) | get-folder $thisFolder.Parent | where {$_.Type -eq "Network"} | new-folder $thisFolder.Name -confirm:$false  -ErrorAction SilentlyContinue}

#Utiilze $DVSLocations line items to create a DVS in the captured folder structure
foreach($line in $DVSLocations){
    $y = 1
    $DVSName = $line.0
    DO{
      IF($line.$y -ne "network"){$y++}
      IF($line.1 -eq "network"){$y=0}
      }
    Until ($line.$y -eq "network" -or $y -eq 0)
    If($y -eq 0){
    $rootname = $line.1
    $root = get-folder | where {$_.Name -eq $rootname}
    New-VDSwitch -BackupPath "$subdir\$DVSName-Export.zip" -Name $DVSName -Location $root 
    }
    Else{
    $count = $y-1
    $rootname = $line.$y
    $root = get-folder | where {$_.Name -eq $rootname}
    $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
        If($subroot.Name -ne $line.1){
            DO{
            $count--
            $root = $subroot
            $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            }
            Until($line.1 -eq $Subroot.name)
    New-VDSwitch -BackupPath "$subdir\$DVSName-Export.zip" -Name $DVSName -Location $subroot 
        }
    }
}
}

#End of Staging, Begining of move processes, all object must reside in target for this to function!
IF($staging -eq $False -and $prepopulatecheck -eq $True){

#Move Hosts into into DVS...utilize Jason's Script for this

#migrate PortGroups to their Correct Folders
    foreach($line in $PortGroupLocations){
        $y = 1
        $PGName = $line.0
        DO{
          IF($line.$y -ne "network"){$y++}
          IF($line.1 -eq "network"){$y=0}
          }
        Until ($line.$y -eq "network" -or $y -eq 0)
        If($y -eq 0){
        Write-Host "No need to move $PGName, already exists at $datacenter root"
        }
        Else{
        $count = $y-1
        $rootname = $line.$y
        $root = get-folder | where {$_.Name -eq $rootname}
        $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            If($subroot.Name -ne $line.1){
                DO{
                $count--
                $root = $subroot
                $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
                }
                Until($line.1 -eq $Subroot.name)
        $PortGroupView = get-view -ViewType Network -Filter @{“Name”=$PGname}
        $pgMoRef = $PortGroupView.MoRef
        $DestinationFolder = get-folder $subroot | Get-View
            If($DestinationFolder.name -eq $subroot){
            $DestinationFolder.MoveIntoFolder($pgMoRef)
            }
            }
        }
}
}

#If staging switch is true, and no previous pre-populate occured
IF($staging -eq $True -and $prepopulatecheck -eq $false){
#Change Capture Type to "VM"
$ApplicationType = "VM"

#Reset $directory to Subfolder \VM
$subdir = "$directory\$ApplicationType"

$Datacenter = "VDC"
#Create Folder Structure in new vCenter
foreach ($thisFolder in (import-clixml $subdir\VMfolders.xml | where {!($_.name -eq "VM")})) {(get-datacenter $datacenter) | get-folder $thisFolder.Parent | where {$_.Type -eq "VM"} | new-folder $thisFolder.Name -confirm:$false -ErrorAction: SilentlyContinue}
}
#End of Staging, Begining of move processes, all object must reside in target for this to function!
IF($staging -eq $False -and $prepopulatecheck -eq $True){

#Set Header to be 128...maximum of storage cluster
$header = 0..128

#Gather all csv's from Get-DatastoreStuff.ps1
$TLocation = "TemplateLocations.csv" 
$VMLocation = "VMLocations.csv"
$VAppLocation = "VAppLocations.csv"  

#send all csv information to variables
$TLocations = Import-CSV "$subdir\$TLocation" -delimiter "," -header $header
$VMLocations = Import-CSV "$subdir\$VMLocation" -delimiter "," -header $header
$VAppLocations = Import-CSV "$subdir\$VAppLocation" -delimiter "," -header $header

#Move all Templates to their correct locations
    foreach($line in $TLocations){
        $y = 1
        $TemplateName = $line.0
        DO{
          IF($line.$y -ne "vm"){$y++}
          IF($line.1 -eq "vm"){$y=0}
          }
        Until ($line.$y -eq "vm" -or $y -eq 0)
        If($y -eq 0){
            $rootname = $line.1
            $root = get-folder | where {$_.Name -eq $rootname}
            Move-Template -Template $TemplateName -Destination $root 
        }
        Else{
            $count = $y-1
            $rootname = $line.$y
            $root = get-folder | where {$_.Name -eq $rootname}
            $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            If($subroot.Name -ne $line.1){
                DO{
                Write-Host "Shouldnt have run do loop"
                $count--
                $root = $subroot
                $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
                }
                Until($line.1 -eq $Subroot.name)
            Move-Template -Template $TemplateName -Destination $subroot 
            }
        }
    }
#Move all vApps to their correct locations..warn.
    foreach($line in $VAppLocations){
        $y = 1
        $vAppName = $line.0
        DO{
          IF($line.$y -ne "vm"){$y++}
          IF($line.1 -eq "vm"){$y=0}
          }
        Until ($line.$y -eq "vm" -or $y -eq 0)
        If($y -eq 0){
            $rootname = $line.1
            $root = get-folder | where {$_.Name -eq $rootname}
            Move-VApp $vAppName -Destination $root 
        }
        Else{
            $count = $y-1
            $rootname = $line.$y
            $root = get-folder | where {$_.Name -eq $rootname}
            $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            If($subroot.Name -ne $line.1){
                DO{
                $count--
                $root = $subroot
                $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
                }
                Until($line.1 -eq $Subroot.name)
            Move-VApp $vAppName -Destination $subroot 
             }
        }
    Write-Host "WARNING: The vApp Named: $vAppName must be re-created after migration"
    }
#Move all VMs to their correct locations
    foreach($line in $VMLocations){
        $y = 1
        $VMName = $line.0
        DO{
            IF($line.$y -ne "vm"){$y++}
            IF($line.1 -eq "vm"){$y=0}
        }
        Until ($line.$y -eq "vm" -or $y -eq 0)
        If($y -eq 0){
        $rootname = $line.1
        $root = get-folder | where {$_.Name -eq $rootname}
        Move-VM -VM $VMName -Destination $root 
        }
        Else{
        $count = $y-1
        $rootname = $line.$y
        $root = get-folder | where {$_.Name -eq $rootname}
        $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            If($subroot.Name -ne $line.1){
                DO{
                $count--
                $root = $subroot
                $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
                }
                Until($line.1 -eq $Subroot.name)
        Move-VM -VM $VMName -Destination $subroot 
            }
        }
    }
}
