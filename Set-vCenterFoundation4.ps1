param
(
	[alias("d")]
	$Directory =  "Enter your Directory provided at the end of the Get-vCenterFoundation Script",
    [alias("vc")]
	$vCenter = "Enter the vCenter of the VIServer you would like to export",
    [bool]$staging  = $true
)

$Directory = "C:\Utils\Migration\VDCVCENTER"
$vCenter = "VDCVCMGMT1"
$staging = $false

#Just incase you ran this from Powershell...
Add-PSSnapin VMWare* -ErrorAction SilentlyContinue

#Change Warning preference to make the script pretty..
$WarningPreference = "SilentlyContinue"

#Clearscreen..
cls

#Convert to Upper
$vCenter = $vcenter.ToUpper()

switch($staging)
{
    $false {Write-Host "You are preforming migration of object into pre-populated Folders,Clusters,DVSwitches within the following vCenter :$vCenter, if you have not pre-populated, the script will also pre-populate the vCenter Correctly" -ForegroundColor Red; break}
    default {Write-Host 'You are only pre-polulating the new vCenter with all captured Folders, Clusters, DVSwitches. This script will not move any objects into the created Folders, Clusters, DVSwitches. You must run the script with the "-staging $false" switch to move objects.' -ForegroundColor DarkGreen ; break}
}

$confirm = Read-Host "Are you sure you want to continue? (Yes/No)"
IF($confirm -like "n" -or $confirm -like "no")
{
    Write-Host "Please re-run the script with the desired switches" -ForegroundColor Yellow
    Write-Host "No Actions Taken" -ForegroundColor Yellow
    ;Break
}

#Connect to the VI Server specified..
Try{
Write-Host "Connecting to Source vCenter" -ForegroundColor Yellow
Connect-VIServer -Server $vCenter -WarningAction SilentlyContinue -erroraction Stop
}
Catch{
Write-Host "Connection to Source vCenter failed, most likely due to a network error or incorrect credentials, please re-run the script with the correct parameters and try again" -ForegroundColor Red
exit
}

#Connected Information
cls
Write-host "Successfully Connected to $vCenter, moving forward with Foundation Application" -ForegroundColor Green
Write-host "=========================================================================="
#Trim and set target directory for where the exported files exist

#Trim user inputed directory for where the exported files exist
$directory = $directory.trim("\")

#set global directory
$globaldir = "$Directory\GlobalSettings\"

<#Not Included in release 4, caused too many issues, wasnt complete
#Read in Roles from GlobalSettings and create those Roles
foreach ($thisRole in (import-clixml $globaldir\roles.xml)){if (!(get-virole $thisRole.name -erroraction silentlycontinue)){new-virole -name $thisRole.name -Privilege (get-viprivilege -id $thisRole.PrivilegeList)}}
#Read in Permissions from GlobalSettings  and assign those permissions
foreach ($thisPerm in (import-clixml $globaldir\permissions.xml)) {get-folder $thisPerm.entity.name | new-vipermission -role $thisPerm.role -Principal $thisPerm.principal -propagate $thisPerm.Propagate}
$allPerms = import-clixml $globaldir\permissions.xml
foreach ($thisPerm in $allPerms) {get-datacenter $thisPerm.entity.name | new-vipermission -role $thisPerm.role -Principal $thisPerm.principal -propagate $thisPerm.Propagate}#>


#Set the directory for where exports exist

$getDCs = Get-ChildItem $Directory -Directory | where {$_.Name -ne "GlobalSettings"}

#get Date
$Date = get-date

#Set Header to be 128...
$header = 0..128

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
        new-item -path $directory -Name Migration-log.txt -type "file"| Out-Null
        }
        Add-Content -Path $directory\Migration-log.txt -Value "`nStage Only at: $Date Target vCenter: $vCenter"| Out-Null
}

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

Foreach($GetDC in $getDCs){
$Directory = "$Directory\$GetDC"
$datacenter = $getDC

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
$SFLocations = "StorageFolderLocations.csv"

#send all csv information to variables
$StorageClusterLocations = Import-CSV "$subdir\$DSCLocation" -delimiter "," -header $header
$StorageCLusterSettings = Import-CSV "$subdir\$DSCConfig"
$ClusterDatastoreLocations = Import-CSV "$subdir\$CDLocations" -delimiter "," -header $header
$VMAffinitySettings = Import-CSV "$subdir\$VMAffinity"
$FolderDatastoreLocations = Import-CSV "$subdir\$FDLocations" -delimiter "," -header $header
$StorageFolderLocations = Import-CSV "$subdir\$SFLocations" -delimiter "," -header $header

#If staging switch is true, and no previous pre-populate occured
IF($staging -eq $True -and $prepopulatecheck -eq $false){
Write-Host "Checking datacenter $datacenter's existance"
#Create Datacenter if not created already
IF(Get-Datacenter -name $datacenter -ErrorAction SilentlyContinue){
    Write-Host "Found $datacenter in $vCenter"
    Add-Content $log -value "Found $datacenter in $vCenter"
    }
Else{New-Datacenter -Name $datacenter -Location (Get-Folder | where {$_.name -eq "Datacenters"}) | Out-File $log -Encoding default -Append}
Write-Host "Creating Storage Folder Structure"
#Create Folder Structure for Storage
foreach($line in $StorageFolderLocations){
    $y = 1
    $EndFolderName = $line.0
    DO{
        IF($line.$y -ne "datastore"){$y++}
        IF($line.1 -eq "datastore"){$y=0}
    }
    Until ($line.$y -eq "datastore" -or $y -eq 0)
    If($y -eq 0){
    $rootname = $line.1
    $root = get-folder | where {$_.Name -eq $rootname -and $_.Type -eq "datastore"}
    If(!(Get-folder -Name $EndFolderName -Location $root -ErrorAction SilentlyContinue)){New-folder -Name $EndFolderName  -Location $root| Out-File $log -Encoding default -Append}
    }
    Else{
    $count = $y-1
    $rootname = $line.$y
    $root = get-folder | where {$_.Name -eq $rootname -and $_.Type -eq "datastore"}
        IF(!(Get-folder -Name $line.$count -ErrorAction SilentlyContinue | Where {$_.Parent -eq $root})){$root | New-Folder -Name $line.$count| Out-File $log -Encoding default -Append}
        $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
        If($subroot.Name -ne $line.1){
            DO{
            $count--
            $root = $subroot
                IF(!(Get-folder -Name $line.$count -ErrorAction SilentlyContinue | Where {$_.Parent -eq $root})){$root | New-Folder -Name $line.$count| Out-File $log -Encoding default -Append}
                $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            }
            Until($line.1 -eq $Subroot.name)
        }
        IF(!(Get-folder -Name $EndFolderName -Location $subroot -ErrorAction SilentlyContinue)){New-folder -Name $EndFolderName  -Location $subroot| Out-File $log -Encoding default -Append}
    }
}

#Create Storage Clusters through a means of complicated methods..done to ensure the right folder is selected, and not in another directory with the same name on accident.
Write-Host "Creating Storage Clusters"
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
    New-DatastoreCluster -Name $SClusterName -Location $root | Out-File $log -Encoding default -Append
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
    New-DatastoreCluster -Name $SClusterName -Location $subroot | Out-File $log -Encoding default -Append
    }
}

#Set Datastore Cluster Captured Settings from CSV
Write-Host "Modifying Storage Cluster's settings"
    foreach($setting in $StorageCLusterSettings){
    $IOLBEnabled = [System.Convert]::ToBoolean($Setting.IOLoadBalanceEnabled)
    Set-DatastoreCluster -DatastoreCluster $Setting.Name -IOLatencyThresholdMillisecond $Setting.IOLatencyThresholdMillisecond -IOLoadBalanceEnabled $IOLBEnabled -SdrsAutomationLevel $Setting.SdrsAutomationLevel -SpaceUtilizationThresholdPercent $Setting.SpaceUtilizationThresholdPercent | Out-File $log -Encoding default -Append
    }
#Set Intra VM Affinity Settings within each DS Cluster from CSV Capture
Write-Host "Modifying Storage Cluster VM Affinity Settings"
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
Write-Host "Moving Datastores Into Datastore Clusters"
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
        Move-Datastore -Datastore $datastore -Destination $SClusterName | Out-File $log -Encoding default -Append
        $count = $count-1
        }
        Until($count -eq 0)
    }
#Move Datastores into Folders
Write-Host "Moving Datastores Into Folders"
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
        Move-Datastore -Datastore $DatastoreName -Destination $root | Out-File $log -Encoding default -Append
        }
        Else{
        $count = $y-1
        $rootname = $line.$y
        $root = get-folder | where {$_.Name -eq $rootname}
        $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            If($subroot.Name -ne $line.1){
                DO{
                write-host "loop"
                $count--
                $root = $subroot
                $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
                }
                Until($line.1 -eq $Subroot.name)
            }
        Move-Datastore -Datastore $DatastoreName -Destination $subroot | Out-File $log -Encoding default -Append
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
$HCFLocations = "HostandClusterFolderLocations.csv"

#send all csv information to variables
$HostClusterSettings = Import-CSV "$subdir\$HCConfig"
$HostClusterLocations = Import-CSV "$subdir\$HCLocation" -delimiter "," -header $header
$ClusterHostLocations = Import-CSV "$subdir\$CHLocations" -delimiter "," -header $header
$HostHostProfiles = Import-CSV "$subdir\$HHPLocations" -delimiter "," -header $header
$ClusterHostProfiles = Import-CSV "$subdir\$CHPLocations" -delimiter "," -header $header
$FolderHostLocations = Import-CSV "$subdir\$FHLocations" -delimiter "," -header $header
$HostClusterFolderLocations = Import-CSV "$subdir\$HCFLocations" -delimiter "," -header $header

#If staging switch is true, and no previous pre-populate occured
IF($staging -eq $True -and $prepopulatecheck -eq $false){

#Create Folder Structure for Host and Clusters
foreach($line in $HostClusterFolderLocations){
    $y = 1
    $EndFolderName = $line.0
    DO{
        IF($line.$y -ne "host"){$y++}
        IF($line.1 -eq "host"){$y=0}
    }
    Until ($line.$y -eq "host" -or $y -eq 0)
    If($y -eq 0){
    $rootname = $line.1
    $root = get-folder | where {$_.Name -eq $rootname -and $_.Type -eq "HostAndCluster"}
    If(!(Get-folder -Name $EndFolderName -Location $root -ErrorAction SilentlyContinue)){New-folder -Name $EndFolderName  -Location $root| Out-File $log -Encoding default -Append}
    }
    Else{
    $count = $y-1
    $rootname = $line.$y
    $root = get-folder | where {$_.Name -eq $rootname -and $_.Type -eq "HostAndCluster"}
        IF(!(Get-folder -Name $line.$count -ErrorAction SilentlyContinue | Where {$_.Parent -eq $root})){$root | New-Folder -Name $line.$count| Out-File $log -Encoding default -Append}
        $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
        If($subroot.Name -ne $line.1){
            DO{
            $count--
            $root = $subroot
                IF(!(Get-folder -Name $line.$count -ErrorAction SilentlyContinue | Where {$_.Parent -eq $root})){$root | New-Folder -Name $line.$count| Out-File $log -Encoding default -Append}
                $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            }
            Until($line.1 -eq $Subroot.name)
        }
        IF(!(Get-folder -Name $EndFolderName -Location $subroot -ErrorAction SilentlyContinue)){New-folder -Name $EndFolderName  -Location $subroot| Out-File $log -Encoding default -Append}
    }
}
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
    New-Cluster -Name $ClusterName -Location $root | Out-File $log -Encoding default -Append
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
    New-Cluster -Name $ClusterName -Location $subroot | Out-File $log -Encoding default -Append
    }
}

#create inclusion list of items you CAN set on a cluster...some you just cant :(
$ParamList = @()
$ParamList = "DrsAutomationLevel","DrsEnabled","DrsMode","HAAdmissionControlEnabled","HAEnabled","HAIsolationResponse","HARestartPriority","VMSwapfilePolicy","EVCMode","VMSwapfilePolicy","HARestartPriority"
$NotAppliedParam = "HAFailoverLevel"

#Set Cluster Captured Settings from CSV
foreach($Cluster in $HostCLusterSettings){
    $SetClusterParams = @{ErrorAction = "SilentlyContinue"}
    $ClusterName = $Cluster.Name
    $Cluster | Foreach-Object {
    foreach ($property in $_.PSObject.Properties)
    {
        If ($Property.Name -eq "HAFailoverLevel" -and $property.Value -eq 0){
            Write-Host "Warning: In order to Migrate to a 6.0 Environment, HA failover mode for cluster $Cluster had to be set to greater then 1 Host, Please change "$Property.Name" setting after the fact, it was orginally "$Property.Value}
        foreach ($param in $ParamList){
            IF($Property.Name -eq $Param){
                $property.Name
                If ($Property.Value){
                    $property.Value
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
    }
Set-Cluster -Cluster $ClusterName @SetClusterParams -Confirm:$false | Out-File $log -Encoding default -Append
}
}

#End of Staging, Begining of move processes, all object must reside in target for this to function!
IF($staging -eq $False -and $prepopulatecheck -eq $True){

#Import DRS Rules once VMs and Hosts exist in Clusters
    foreach($Cluster in $HostCLusterSettings){
    Import-DrsRule -Path "$subdir\$ClusterName-DRSRules.json" -Cluster $ClusterName | Out-File $log -Encoding default -Append
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
        Move-VMHost -VMHost $VMhost -Destination $ClusterName | Out-File $log -Encoding default -Append
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
        Move-VMHost -VMHost $VMhost -Destination $root | Out-File $log -Encoding default -Append
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
        Move-VMHost -VMHost $VMhost -Destination $subroot | Out-File $log -Encoding default -Append
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
        Import-VMHostProfile -FilePath "$subdir\$HPName-HostProfile.prf" -Name $HPName -ReferenceHost $RefHost | Out-File $log -Encoding default -Append
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
        Apply-VMHostProfile -Entity $Cluster -Profile $HPName -AssociateOnly -Confirm:$false | Out-File $log -Encoding default -Append
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
    Apply-VMHostProfile -Entity $VMHost -Profile $Profile -AssociateOnly -Confirm:$false | Out-File $log -Encoding default -Append
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
$NFLocations = "NetworkFolderLocations.csv"


#send all csv information to variables
$DVSLocations = Import-CSV "$subdir\$DVSLocation" -delimiter "," -header $header
$PortGroupLocations = Import-CSV "$subdir\$PGLocations" -delimiter "," -header $header
$NetworkFolderLocations = Import-CSV "$subdir\$NFLocations" -delimiter "," -header $header

#If staging switch is true, and no previous pre-populate occured
IF($staging -eq $True -and $prepopulatecheck -eq $false){

#Create Folder Structure for Networking
foreach($line in $NetworkFolderLocations){
    $y = 1
    $EndFolderName = $line.0
    DO{
        IF($line.$y -ne "network"){$y++}
        IF($line.1 -eq "network"){$y=0}
    }
    Until ($line.$y -eq "network" -or $y -eq 0)
    If($y -eq 0){
    $rootname = $line.1
    $root = get-folder | where {$_.Name -eq $rootname -and $_.Type -eq "Network"}
    If(!(Get-folder -Name $EndFolderName -Location $root -ErrorAction SilentlyContinue)){New-folder -Name $EndFolderName  -Location $root| Out-File $log -Encoding default -Append}
    }
    Else{
    $count = $y-1
    $rootname = $line.$y
    $root = get-folder | where {$_.Name -eq $rootname -and $_.Type -eq "Network"}
        IF(!(Get-folder -Name $line.$count -ErrorAction SilentlyContinue | Where {$_.Parent -eq $root})){$root | New-Folder -Name $line.$count| Out-File $log -Encoding default -Append}
        $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
        If($subroot.Name -ne $line.1){
            DO{
            $count--
            $root = $subroot
                IF(!(Get-folder -Name $line.$count -ErrorAction SilentlyContinue | Where {$_.Parent -eq $root})){$root | New-Folder -Name $line.$count| Out-File $log -Encoding default -Append}
                $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            }
            Until($line.1 -eq $Subroot.name)
        }
        IF(!(Get-folder -Name $EndFolderName -Location $subroot -ErrorAction SilentlyContinue)){New-folder -Name $EndFolderName  -Location $subroot| Out-File $log -Encoding default -Append}
    }
}

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
    New-VDSwitch -BackupPath "$subdir\$DVSName-Export.zip" -Name $DVSName -Location $root | Out-File $log -Encoding default -Append
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
    New-VDSwitch -BackupPath "$subdir\$DVSName-Export.zip" -Name $DVSName -Location $subroot | Out-File $log -Encoding default -Append
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
        If($y -ne 0){
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


#If staging switch is true, and no previous pre-populate occured
IF($staging -eq $True -and $prepopulatecheck -eq $false){
#Change Capture Type to "VM"
$ApplicationType = "VM"

#Reset $directory to Subfolder \VM
$subdir = "$directory\$ApplicationType"

#Set Header to be 128...maximum of storage cluster
$header = 0..128

#Gather all csv's from Get-DatastoreStuff.ps1
$TLocation = "TemplateLocations.csv" 
$VMLocation = "VMLocations.csv"
$VAppLocation = "VAppLocations.csv"
$VMFLocations = "VMFolderLocations.csv"

#send all csv information to variables
$TLocations = Import-CSV "$subdir\$TLocation" -delimiter "," -header $header
$VMLocations = Import-CSV "$subdir\$VMLocation" -delimiter "," -header $header
$VAppLocations = Import-CSV "$subdir\$VAppLocation" -delimiter "," -header $header
$VMFolderLocations = Import-CSV "$subdir\$VMFLocations" -delimiter "," -header $header

#Create Folder Structure for VMs 
foreach($line in $VMFolderLocations){
    $y = 1
    $EndFolderName = $line.0
    DO{
        IF($line.$y -ne "vm"){$y++}
        IF($line.1 -eq "vm"){$y=0}
    }
    Until ($line.$y -eq "vm" -or $y -eq 0)
    If($y -eq 0){
    $rootname = $line.1
    $root = get-folder | where {$_.Name -eq $rootname -and $_.Type -eq "vm"}
        If(!(Get-folder -Name $EndFolderName -Location $root -ErrorAction SilentlyContinue)){New-folder -Name $EndFolderName  -Location $root| Out-File $log -Encoding default -Append}
    }
    Else{
    $count = $y-1
    $rootname = $line.$y
    $root = get-folder | where {$_.Name -eq $rootname -and $_.Type -eq "vm"}
        IF(!(Get-folder -Name $line.$count -ErrorAction SilentlyContinue | Where {$_.Parent -eq $root})){$root | New-Folder -Name $line.$count| Out-File $log -Encoding default -Append}
        $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
        If($subroot.Name -ne $line.1){
            DO{
            $count--
            $root = $subroot
                IF(!(Get-folder -Name $line.$count -ErrorAction SilentlyContinue | Where {$_.Parent -eq $root})){$root | New-Folder -Name $line.$count| Out-File $log -Encoding default -Append}
                $subroot = $root | Get-folder -Name $line.$count | Where {$_.Parent -eq $root}
            }
            Until($line.1 -eq $Subroot.name)
        }
        IF(!(Get-folder -Name $EndFolderName -Location $subroot -ErrorAction SilentlyContinue)){New-folder -Name $EndFolderName  -Location $subroot| Out-File $log -Encoding default -Append}
    }
}
#End of Staging, Begining of move processes, all object must reside in target for this to function!
IF($staging -eq $False -and $prepopulatecheck -eq $True){


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
        Move-Template -Template $TemplateName -Destination $root | Out-File $log -Encoding default -Append
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
    Move-Template -Template $TemplateName -Destination $subroot | Out-File $log -Encoding default -Append
    }
}
#Move all vApps to their correct locations..warn.
foreach($line in $VAppLocations){
    Write-Host "WARNING: The vApp Named: $vAppName must be re-created after migration"
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
        Move-VApp $vAppName -Destination $root | Out-File $log -Encoding default -Append
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
    Move-VApp $vAppName -Destination $subroot  | Out-File $log -Encoding default -Append
    }
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
    Move-VM -VM $VMName -Destination $root | Out-File $log -Encoding default -Append
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
    Move-VM -VM $VMName -Destination $subroot | Out-File $log -Encoding default -Append
    }
}
Import-Csv -Path $subdir\Migration-VMAnnotations.csv | Where-Object {$_.Value} | ForEach-Object {
Get-VM $_.VM | Set-Annotation -CustomAttribute $_.Name -Value $_.Value | Out-File $log -Encoding default -Append
}
}
}
}

