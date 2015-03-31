Function GetBoundaryInformation {
    Param (
    $CopyToClipBoard = $false, 
    [Parameter(Mandatory=$true)]
    $SiteCode,
    [Parameter(Mandatory=$true)]
    $SiteServer
    )

    $output = @()
    Get-WmiObject -Namespace "root\sms\site_$SiteCode" -ComputerName $SiteServer -Query "select * from SMS_BoundaryGroup" | ForEach-Object {
        $groupname = $_.name
        $stroutput = "Group Name: $groupname"
        $output += @($stroutput)
        $groupid = $_.groupid
        $groupmembership = Get-WmiObject -Namespace "root\sms\site_ps1" -Query "select * from sms_boundarygroupmembers where groupid = '$groupid'"
        foreach ( $instance in $groupmembership) {
            $boundaryid = $instance.boundaryid
            $boundary = Get-WmiObject -Namespace "root\sms\site_ps1" -Query "select * from sms_boundary where boundaryid = '$boundaryid'"
            $stroutput = "`tName: " + $boundary.displayname + "`t`t`t`tRange: " + $boundary.value
            $output += @($stroutput)
        }
    }
    if ($CopyToClipBoard) { $output | clip.exe }
    $output
}