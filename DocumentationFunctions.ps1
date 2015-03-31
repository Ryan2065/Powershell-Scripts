Function BoundaryGroupInformation {
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
        $stroutput = "Group: $groupname"
        $output += @($stroutput)
        $output += @("Included Boundaries:")
        $output += @("Boundary Name`tValue")
        $groupid = $_.groupid
        $groupmembership = Get-WmiObject -Namespace "root\sms\site_ps1" -Query "select * from sms_boundarygroupmembers where groupid = '$groupid'"
        foreach ( $instance in $groupmembership) {
            $boundaryid = $instance.boundaryid
            $boundary = Get-WmiObject -Namespace "root\sms\site_ps1" -Query "select * from sms_boundary where boundaryid = '$boundaryid'"
            $stroutput = $boundary.displayname + "`t" + $boundary.value
            $output += @($stroutput)
        }
    }
    if ($CopyToClipBoard) { $output | clip.exe }
    $output
}

Function BoundaryInformation {
    Param (
    $CopyToClipBoard = $false, 
    [Parameter(Mandatory=$true)]
    $SiteCode,
    [Parameter(Mandatory=$true)]
    $SiteServer
    )

    $output = @()
    $strOutput = "Display Name`tType`tValue"
    $output += @($strOutput)
    Get-WmiObject -Namespace "root\sms\site_$SiteCode" -ComputerName $SiteServer -Query "select * from SMS_Boundary" | ForEach-Object {
        $DisplayName = $_.DisplayName
        $Value = $_.Value
        $Type = $_.BoundaryType
        Switch ($Type) {
            0 { $type = "IP Subnet" }
            1 { $type = "AD Site" }
            2 { $type = "IPV6 Prefix" }
            3 { $type = "IP Range" }
        }
        $stroutput = "$DisplayName`t$type`t$value"
        $output += @($stroutput)
    }
    if ($CopyToClipBoard) { $output | clip.exe }
    $output
}

Function DistributionPointInformation-ParseSchedule {
    Param ($Schedule)
    Switch ($Schedule) {
        1 { return "Open for all priorities" }
        2 { return "Allow medium and high priority" }
        3 { return "Allow high priority only" }
        4 { return "Closed" }
    }
}

Function DistributionPointInformation {
    Param (
    $CopyToClipBoard = $false, 
    [Parameter(Mandatory=$true)]
    $SiteCode,
    [Parameter(Mandatory=$true)]
    $SiteServer
    )
    $output = @()
    Get-WmiObject -Namespace "root\sms\site_$SiteCode" -ComputerName $SiteServer -Query "Select * from SMS_DistributionPointInfo" | ForEach-Object {
        $ServerName = $_.ServerName
        $output += @("DP Name: $ServerName")
        $PXEEnabled = $_.IsPXE
        $MulticastEnabled = $_.IsMulticast
        $PullDPEnabled = $_.IsPullDP
        $FallbackDP = $_.IsProtected
        $DPGroupCount = $_.GroupCount
        $Prestaged = $_.PreStagingAllowed
        $output += @("`tPXE Enabled: $PXEEnabled")
        $output += @("`tMulticast Enabled: $MulticastEnabled")
        $output += @("`tPull DP: $PullDPEnabled")
        $output += @("`tFallback DP: $FallbackDP")
        $output += @("`tPrestaged: $Prestaged")
        $output += @("`tDP Group Count: $DPGroupCount")
        $SCIAddress = Get-WmiObject -Namespace "root\sms\site_$SiteCode" -ComputerName $SiteServer -Query "select * from SMS_SCI_Address where DesSiteCode = '$ServerName'"
        if ($SCIAddress -eq $null) {
            $output += @("`tNo Schedule Set")
            $output += @("`tRate Limit: Unlimited when sending to this destination")
        }
        foreach ($instance in $SCIAddress) {
            if ($_.AddressScheduleEnabled -eq $true) {
                $output += @("`tSchedule:")
                $instance.get()
                $UsageSchedule = $instance.UsageSchedule
                $Schedule = $UsageSchedule.HourUsage
                $count = 0
                $TempOutput = ""
                $PreviousVariable = $null
                foreach ($hour in $Schedule) {
                    if ($count -le 23) {
                        If ($Count -eq 0) { 
                            $PreviousVariable = $hour
                            $TempOutput = "`t`tSunday 1 - " 
                        }
                        elseif (($PreviousVariable -ne $hour) -or ($count -eq 23)) {
                            $FriendlyName = DistributionPointInformation-ParseSchedule $hour
                            $FriendlyHour = $count + 1
                            $TempOutput = $TempOutput + "$FriendlyHour" + ": $FriendlyName"
                            $output += @($TempOutput)
                            $TempOutput = "`t`tSunday " + $count + " - "
                            $PreviousVariable = $hour
                            if ($count -eq 23) { $PreviousVariable = $null }
                        }
                     }
                     elseif ($count -le 47) {
                        If ($Count -eq 24) { 
                            $PreviousVariable = $hour
                            $TempOutput = "`t`tMonday 1 - " 
                        }
                        elseif (($PreviousVariable -ne $hour) -or ($count -eq 47)) {
                            $FriendlyName = DistributionPointInformation-ParseSchedule $PreviousVariable
                            $CorrectHour = $count - 23
                            $TempOutput = $TempOutput + "$CorrectHour" + ": $FriendlyName"
                            $output += @($TempOutput)
                            $CorrectHour++
                            $TempOutput = "`t`tMonday " + $CorrectHour + " - "
                            $PreviousVariable = $hour
                            if ($count -eq 47) { $PreviousVariable = $null }
                        }
                     }
                     elseif ($count -le 71) {
                        If ($Count -eq 48) { 
                            $PreviousVariable = $hour
                            $TempOutput = "`t`tTuesday 1 - " 
                        }
                        elseif (($PreviousVariable -ne $hour) -or ($count -eq 71)) {
                            $FriendlyName = DistributionPointInformation-ParseSchedule $PreviousVariable
                            $CorrectHour = $count - 47
                            $TempOutput = $TempOutput + "$CorrectHour" + ": $FriendlyName"
                            $output += @($TempOutput)
                            $CorrectHour++
                            $TempOutput = "`t`tTuesday $CorrectHour - "
                            $PreviousVariable = $hour
                            if ($count -eq 71) { $PreviousVariable = $null }
                        }
                    }
                     elseif ($count -le 95) {
                        If ($Count -eq 72) { 
                            $PreviousVariable = $hour
                            $TempOutput = "`t`tWednesday 1 - " 
                        }
                        elseif (($PreviousVariable -ne $hour) -or ($count -eq 95)) {
                            $FriendlyName = DistributionPointInformation-ParseSchedule $PreviousVariable
                            $CorrectHour = $count - 71
                            $TempOutput = $TempOutput + "$CorrectHour" + ": $FriendlyName"
                            $output += @($TempOutput)
                            $CorrectHour++
                            $TempOutput = "`t`tWednesday $CorrectHour - "
                            $PreviousVariable = $hour
                            if ($count -eq 71) { $PreviousVariable = $null }
                        }
                    }
                     elseif ($count -le 119) {
                        If ($Count -eq 96) { 
                            $PreviousVariable = $hour
                            $TempOutput = "`t`tThursday 1 - " 
                        }
                        elseif (($PreviousVariable -ne $hour) -or ($count -eq 119)) {
                            $FriendlyName = DistributionPointInformation-ParseSchedule $PreviousVariable
                            $CorrectHour = $count - 95
                            $TempOutput = $TempOutput + "$CorrectHour" + ": $FriendlyName"
                            $output += @($TempOutput)
                            $CorrectHour++
                            $TempOutput = "`t`tThursday $CorrectHour - "
                            $PreviousVariable = $hour
                            if ($count -eq 71) { $PreviousVariable = $null }
                        }
                    }
                     elseif ($count -le 143) {
                        If ($Count -eq 120) { 
                            $PreviousVariable = $hour
                            $TempOutput = "`t`tFriday 1 - " 
                        }
                        elseif (($PreviousVariable -ne $hour) -or ($count -eq 143)) {
                            $FriendlyName = DistributionPointInformation-ParseSchedule $PreviousVariable
                            $CorrectHour = $count - 119
                            $TempOutput = $TempOutput + "$CorrectHour" + ": $FriendlyName"
                            $output += @($TempOutput)
                            $CorrectHour++
                            $TempOutput = "`t`tFriday $CorrectHour - "
                            $PreviousVariable = $hour
                            if ($count -eq 71) { $PreviousVariable = $null }
                        }
                    }
                     elseif ($count -le 167) {
                        If ($Count -eq 144) { 
                            $PreviousVariable = $hour
                            $TempOutput = "`t`tSaturday 1 - " 
                        }
                        elseif (($PreviousVariable -ne $hour) -or ($count -eq 167)) {
                            $FriendlyName = DistributionPointInformation-ParseSchedule $PreviousVariable
                            $CorrectHour = $count - 143
                            $TempOutput = $TempOutput + "$CorrectHour" + ": $FriendlyName"
                            $output += @($TempOutput)
                            $CorrectHour++
                            $TempOutput = "`t`tSaturday $CorrectHour - "
                            $PreviousVariable = $hour
                            if ($count -eq 71) { $PreviousVariable = $null }
                        }
                    }
                $count++
                }
            }
            else { $output += @("No Schedule Set") }
                $RateLimitingSchedule = $instance.RateLimitingSchedule
                $RateScheduleCount = $_.RateLimitingSchedule.Count
                if ($instance.UnlimitedRateForAll -eq $true) {
                    $output += @("`tRate Limit: Unlimited when sending to this destination")
                }
                elseif ($RateScheduleCount -ne $null) {
                    $output += @("`tRate Limit: Limited to specified maximum transfer rates by hour")
                    $count = 0
                    $PreviousValue = $null
                    $stroutput = ""
                    Foreach ($Rate in $instance.RateLimitingSchedule) {
                        $count++
                        if ($PreviousValue -ne $Rate) {
                            if ($count -eq 1) { $stroutput = "`t`t$Count" + " - " }
                            else {
                                $stroutput = $stroutput + "$count" + ": " + $PreviousValue + "%"
                                $output += @($stroutput)
                                $newCount = $count + 1
                                $stroutput = "`t`t$NewCount - "
                            }
                            $PreviousValue = $Rate
                        }
                    }
                    $stroutput = $stroutput + "24: " + $PreviousValue + "%"
                    $output += @($stroutput)
                }
                else {
                    $output += @("`tRate Limit: Pulse Mode")
                }
            }
    }
    if ($CopyToClipBoard) { $output | clip.exe }
    $output
}

DistributionPointInformation -CopyToClipBoard $true -SiteCode "ps1" -SiteServer "mn04sccm01"