#Add-PSSnapin VMware*
#Connect-VIServer -Server goldvc1p
param
(
	[alias("d")]
	$directory =  "E:\tmp\GOLD\",
	[alias("dc")]
	$datacenter = "GOLD"
)

$directory = $directory.trim("\")
new-item $directory -type directory -erroraction silentlycontinue
$dc = get-datacenter $datacenter
$HostClusters = $dc | Get-Cluster
$Hosts = $dc | Get-VMHost
$dc | get-folder | where {$_.type -eq "HostAndCluster"} | select name,parent | export-clixml $directory\HostandClusterfolders.xml

$folders = Get-Folder | where {$_.Type -eq "HostAndCluster"}
$rootHostandClusterFolder = Get-Folder | where {$_.type -eq "HostAndCluster" -and $_.Parent.Name -eq $dc.Name}

foreach($Cluster in $HostClusters){
$findClusterParent = $Cluster.ParentId
    foreach($folder in $folders){
    $HostClusterLocation = @()
        IF($folder.Id -match $findClusterParent){
            $HostClusterLocation += $Cluster.Name
            DO {
                $HostClusterLocation += $folder.Name
                IF($folder.Name -ne $rootHostandClusterFolder){
                $folder = $folder.Parent.Name
                }
                }
            Until($folder.name -eq "host")
            $HostClusterLocation -join "," >>$directory\HostClusterLocations.csv          
        }
    }
$Cluster | Select * | Export-Csv -Path $directory\HostClusterSettings.csv -Append -NoTypeInformation
$ClusterHostLocations = @()
$ClusterHosts = $Cluster | Get-VMHost
$ClusterHostLocations += $Cluster.Name
$ClusterHostLocations += $ClusterHosts.Name
$ClusterHostLocations -join "," >>$directory\ClusterHostLocations.csv
#Ensure you get VM affinity, DRS Groups, and all other stupid settings.
#Get-Cluster MISC SETTINGS | Export-CSV -Path $directory\StorageClusterVMAffinity.csv -Append -NoTypeInformation
#$Cluster | Get-DrsRule 
}

#the hard way of getting all Host locations..

foreach($VMHost in $Hosts){
$findHostParent = $VMHost.Parent
    foreach($folder in $folders){
    $HostLocation = @()
        IF($folder -eq $findHostParent){
            $HostLocation += $VMHost.Name
            DO {
                $HostLocation += $folder.Name
                IF($folder.Name -ne $rootHostFolder){
                $folder = $folder.Parent
                }
                IF($folder.Name -eq $rootHostFolder){
                $HostLocation += $rootHostFolder
                }
                }
            Until($folder.Name -eq "host")
            $HostLocation += $rootHostFolder
            $HostLocation -join "," >>$directory\HostLocations.csv
        }
    }
}