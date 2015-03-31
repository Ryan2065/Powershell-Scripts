<#
.SYNOPSIS
	Searches through all clients in the CM environment and finds any that are not in a boundary
.DESCRIPTION
.PARAMETER SiteServer
    FQDN of the primary/CAS
.PARAMETER SiteCode
    Site code
.EXAMPLE
	PS C:\PSScript > .\FindDevicesNoBoundary.ps1 -SiteServer CM.Home.Local -SiteCode PS1
    Will check the IP address of all devices in the site and match them up to boundaries / boundary groups
.INPUTS
.OUTPUTS
.LINK
.NOTES
	NAME: FindDevicesNoBoundary.ps1
	VERSION: 1.0
	AUTHOR: Ryan Ephgrave
	LASTEDIT: 03/31/2015
#>

[CmdletBinding() ]
Param (
    [Parameter(Mandatory=$true)]
    $SiteServer,
    [Parameter(Mandatory=$true)]
    $SiteCode
)

$Script:Namespace = "root\sms\site_" + $SiteCode

Function All-Boundaries {
    $Boundaries = New-Object System.Collections.ArrayList
    Get-WmiObject -Namespace $Script:Namespace -ComputerName $SiteServer -Query "Select * From SMS_Boundary" | ForEach-Object {
        $Boundary = Select-Object -InputObject "" Type, Value, Name, DoesContent, SiteAssignment, DefaultSiteCode
        $Boundary.Type = $_.BoundaryType
        $Boundary.Value = $_.Value
        $Boundary.Name = $_.Name
        $BoundarySiteAssignment = $false
        $BoundaryContent = $false
        if ($_.GroupCount -gt 0) {
            If ($_.SiteSystems -ne $null) {
                $BoundaryContent = $true
            }
            If ($_.DefaultSiteCode -ne $null) {
                $BoundarySiteAssignment = $true
            }
        }
        $Boundary.SiteAssignment = $BoundarySiteAssignment
        $Boundary.DoesContent = $BoundaryContent
        $Boundaries.Add($Boundary) | Out-Null
    }
    return $Boundaries
}

Function Compare-IPRange {
    Param ($IPAddress, $IPRange)
	$IPRange = $IPRange.split("-")
	$IpLow = [IPAddress]$IPRange[0]
	$IPHigh = [IPAddress]$IPRange[1]
	$IPToCompare = [IPAddress] $IPAddress
    $IpLowBytes = $IpLow.GetAddressBytes()
    $IPHighBytes = $IPHigh.GetAddressBytes()
    $IPToCompareBytes = $IPToCompare.GetAddressBytes()
    [Array]::Reverse($IpLowBytes)
    [Array]::Reverse($IPHighBytes)
    [Array]::Reverse($IPToCompareBytes)
    $IPLowBit = [System.BitConverter]::ToUInt32($IpLowBytes, 0)
    $IPHighBit = [System.BitConverter]::ToUInt32($IPHighBytes, 0)
    $IPToCompareBit = [System.BitConverter]::ToUInt32($IPToCompareBytes, 0)
    [bool]$InRange
	if (($IPLowBit -le $IPToCompareBit) -and ($IPToCompareBit -le $IPHighBit)) { $InRange = $true }
    else { $InRange = $false }
    return $InRange
}

$Boundaries = All-Boundaries

Get-WmiObject -Namespace $Namespace -ComputerName $SiteServer -Query "Select Name, ADSiteName, IPAddresses, IPSubnets from SMS_R_System" | ForEach-Object {
    $Result = Select-Object -InputObject "" Name, InBoundary, SiteAssignment, Content, IPAddresses, ADSite, IPSubnets, InADSiteBoundary, InIPAddressBoundary, InIPSubnetBoundary
    $Result.Name = $_.Name
    $Result.InBoundary = $false
    $Result.SiteAssignment = $false
    $Result.Content = $false
    $Result.ADSite = $_.ADSiteName
    $Result.IPAddresses = $_.IPAddresses
    $Result.IPSubnets = $_.IPSubnets
    $result.InIPAddressBoundary = $false
    $Result.InADSiteBoundary = $false
    $Result.InIPSubnetBoundary = $false
    Foreach ($Boundary in $Boundaries) {
        If ($Boundary.Type -eq 0) {
            If ($_.IPSubnets -ne $null) {
                foreach ($IPSubnet in $_.IPSubnets) {
                    if ($IPSubnet -eq $Boundary.Value) {
                        $Result.InBoundary = $true
                        $result.InIPSubnetBoundary = $true
                        if ($Boundary.DoesContent) { $Result.Content = $true }
                        if ($Boundary.SiteAssignment) { $Result.SiteAssignment = $true }
                    }
                }
            }
        }
        elseif ($Boundary.Type -eq 1) {
            $CompADSite = $_.ADSiteName
            $BoundaryADSite = $Boundary.Value
            If ($CompADSite -ne $null) {
                If ($CompADSite.ToLower() -eq $BoundaryADSite.ToLower()) {
                    $Result.InBoundary = $true
                    $result.InADSiteBoundary = $true
                    If ($Boundary.DoesContent) { $Result.Content = $true }
                    If ($Boundary.SiteAssignment) { $Result.SiteAssignment = $true }
                }
            }
        }
        elseif ($Boundary.Type -eq 2) {
            #IPV6Prefix
        }
        elseif ($Boundary.Type -eq 3) {
            $IPAddresses = $_.IPAddresses
            foreach ($IP in $IPAddresses) {
                if ($IP.Contains(".")) {
                    If (Compare-IPRange -IPAddress $IP -IPRange $Boundary.Value) { 
                        $Result.InBoundary = $true
                        $result.InIPAddressBoundary = $true
                        If ($Boundary.DoesContent) { $Result.Content = $true }
                        If ($Boundary.SiteAssignment) { $Result.SiteAssignment = $true }
                    }
                }
            }
        }
    }
    $Result
}