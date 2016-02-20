<#
    .SYNOPSIS
        
 
    .DESCRIPTION
        
   
    .EXAMPLE
        
  
    .NOTES
        AUTHOR: 
        LASTEDIT: 02/18/2016 14:07:34
 
   .LINK
        
#>
 
$ScriptName = $MyInvocation.MyCommand.path
$Directory = Split-Path $ScriptName
$Popup = New-Object -ComObject wscript.shell
$TempLocation = $env:TEMP + '\TestApplicationsInHyperV\' + ([GUID]::NewGuid()).GUID
$LogFile = $TempLocation + '\MainLogFile.Log'
$null = New-Item -ItemType Directory -Path $TempLocation -ErrorAction SilentlyContinue

If(!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]"Administrator")){
	Start-Process Powershell.exe -ArgumentList "-STA -noprofile -file `"$ScriptName`"" -Verb RunAs
	Exit
}

Function Install-CMApplication {
    Param(
        $ApplicationName,
        $ComputerName
    )

    $TriedInstall = $false
    try {
        $WMIPath = "\\" + $ComputerName + "\root\ccm\clientsdk:CCM_Application"
	    $WMIClass = [WMIClass] $WMIPath
        $ApplicationID = ""
        $ApplicationRevision = ""
        $IsMachineTarget = ""
	    Get-WmiObject -ComputerName $Script:strCompName -Query "select * from CCM_Application" -Namespace root\ccm\ClientSDK | ForEach-Object {
	        if ($_.Name -eq $ApplicationName) {
	            $ApplicationRevision = $_.Revision
	            $IsMachineTarget = $_.IsMachineTarget
	            $EnforcePreference = $_.EnforcePreference
	            $ApplicationID = $_.ID
                $TriedInstall = $true
	        }
	    }
        if ($TriedInstall) { 
	        $null = $WMIClass.Install($ApplicationID, $ApplicationRevision, $IsMachineTarget, "", "1", $false)
        }
        return $TriedInstall
    }
    catch {
        return $_.Exception.Message
    }
}

Function Log {
    Param (
		[Parameter(Mandatory=$false)]
		$Message,
 
		[Parameter(Mandatory=$false)]
		$ErrorMessage,
 
		[Parameter(Mandatory=$false)]
		$Component,
 
		[Parameter(Mandatory=$false)]
		[int]$Type,
		
		[Parameter(Mandatory=$true)]
		$LogFile
	)
<#
Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
#>
	$Time = Get-Date -Format "HH:mm:ss.ffffff"
	$Date = Get-Date -Format "MM-dd-yyyy"
 
	if ($ErrorMessage -ne $null) {$Type = 3}
	if ($Component -eq $null) {$Component = " "}
	if ($Type -eq $null) {$Type = 1}
 
	$LogMessage = "<![LOG[$Message $ErrorMessage" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
	$LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile
    $Message = "$Message - $ErrorMessage + `n Log Location = $TempLocation"
    Write-Host $Message
}

Function Translate-EvaluationState {
    Param ($EvaluationState)

    $strEvaluationState = ""
    Switch ($EvaluationState) {
        0 { $strEvaluationState = "No state information is available." }
        1 { $strEvaluationState = "Application is enforced to desired/resolved state." }
        2 { $strEvaluationState = "Application is not required on the client." }
        3 { $strEvaluationState = "Application is available for enforcement (install or uninstall based on resolved state). Content may/may not have been downloaded." }
        4 { $strEvaluationState = "Application last failed to enforce (install/uninstall)." }
        5 { $strEvaluationState = "Application is currently waiting for content download to complete." }
        6 { $strEvaluationState = "Application is currently waiting for content download to complete." }
        7 { $strEvaluationState = "Application is currently waiting for its dependencies to download." }
        8 { $strEvaluationState = "Application is currently waiting for a service (maintenance) window." }
        9 { $strEvaluationState = "Application is currently waiting for a previously pending reboot." }
        10 { $strEvaluationState = "Application is currently waiting for serialized enforcement." }
        11 { $strEvaluationState = "Application is currently enforcing dependencies." }
        12 { $strEvaluationState = "Application is currently enforcing." }
        13 { $strEvaluationState = "Application install/uninstall enforced and soft reboot is pending." }
        14 { $strEvaluationState = "Application installed/uninstalled and hard reboot is pending." }
        15 { $strEvaluationState = "Update is available but pending installation." }
        16 { $strEvaluationState = "Application failed to evaluate." }
        17 { $strEvaluationState = "Application is currently waiting for an active user session to enforce." }
        18 { $strEvaluationState = "Application is currently waiting for all users to logoff." }
        19 { $strEvaluationState = "Application is currently waiting for a user logon." }
        20 { $strEvaluationState = "Application in progress, waiting for retry." }
        21 { $strEvaluationState = "Application is waiting for presentation mode to be switched off." }
        22 { $strEvaluationState = "Application is pre-downloading content (downloading outside of install job)." }
        23 { $strEvaluationState = "Application is pre-downloading dependent content (downloading outside of install job)." }
        24 { $strEvaluationState = "Application download failed (downloading during install job)." }
        25 { $strEvaluationState = "Application pre-downloading failed (downloading outside of install job)." }
        26 { $strEvaluationState = "Download success (downloading during install job)." }
        27 { $strEvaluationState = "Post-enforce evaluation." }
        28 { $strEvaluationState = "Waiting for network connectivity." }
    }
    return $strEvaluationState
}

Function LoadApplications {
    Param ($CompName, $WindowDataContext)
	try {
        $null = $WindowDataContext.ApplicationGrid.Clear()
		Get-WmiObject -Query "select * from CCM_Application" -Namespace root\ccm\clientsdk -ComputerName $CompName | ForEach-Object {
			$Results = New-Object -TypeName AppGridClass
			$Results.Name = $_.Name
			if ($Results.Name -ne $null) {$FoundApps = $true}
			$Results.Installed = $_.InstallState
			$ResolvedState = $_.ResolvedState
			If ($ResolvedState -eq "Available") {$Results.Required = "False"}
			else {$Results.Required = "True"}
			$LastEvalTime = $_.LastEvalTime
			if ($LastEvalTime -ne $null) {
				$EvalTime = $_.ConvertToDateTime($_.LastEvalTime)
				$Results.LastEvaluated = $EvalTime.ToShortDateString() + " " + $EvalTime.ToShortTimeString()
			}
			$null = $WindowDataContext.ApplicationGrid += $Results
		}
        Log -Message "Finished loading application list!" -LogFile $LogFile
	}
    catch {
        Log -Message "Error loading applications -" -ErrorMessage $_.Exception.Message -LogFile $LogFile
    }
}

[xml]$xaml = @'
<Window 
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Application Tester" WindowStartupLocation="CenterScreen" Width="600" Height="500" >
    <Grid Margin="5">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="3*"/>
            <ColumnDefinition Width="2*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="30"/>
            <RowDefinition Height="30"/>
            <RowDefinition Height="30"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="90"/>
        </Grid.RowDefinitions>
        <StackPanel Orientation="Horizontal" Grid.Row="0" Grid.Column="0" Grid.ColumnSpan="2">
            <Label Content="Computer Name:"/>
            <TextBox Name="ComputerName" Width="125" Margin="5,0,0,0" Text="{Binding Path=ComputerName}" VerticalContentAlignment="Center" TextWrapping="NoWrap"/>
            <Label Content="VM Name:" Margin="5,0,0,0"/>
            <TextBox Name="VMName" Width="125" Margin="5,0,0,0" VerticalContentAlignment="Center" Text="{Binding Path=VMName}" TextWrapping="NoWrap"/>
            <Button Name="LoadApplications" Width="100" Margin="5,0,0,0" Content="Load Apps"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2">
            <CheckBox Name="UseRemoteHyperV" Content="Use remote Hyper-V Server" VerticalContentAlignment="Center"/>
            <TextBox Width="125" Margin="5,2,0,0" Text="{Binding Path=HyperVServerName}" TextWrapping="NoWrap" VerticalContentAlignment="Center" IsEnabled="{Binding ElementName=UseRemoteHyperV, Path=IsChecked}"/>
            <CheckBox IsChecked="{Binding Path=HyperVServerAltCredsCheckbox}" Content="Use alternate credentials for Hyper-V server" VerticalContentAlignment="Center" Margin="10,0,0,0" IsEnabled="{Binding ElementName=UseRemoteHyperV, Path=IsChecked}"/>
        </StackPanel>
        <Label Content="Applications Advertised to Computer" HorizontalContentAlignment="Center" Grid.Row="2" Grid.Column="0"/>
        <DataGrid Name="ApplicationGrid" IsReadOnly="True" ItemsSource="{Binding Path=ApplicationGrid}" Grid.Row="3" Grid.Column="0" Margin="0,0,5,10">
            <DataGrid.ContextMenu>
                <ContextMenu>
                    <MenuItem Name="AddToList" Header="Add to list"/>
                </ContextMenu>
            </DataGrid.ContextMenu>
        </DataGrid>
        <Label Content="Applications To Test" HorizontalAlignment="Center" Grid.Row="2" Grid.Column="1"/>
        <ListBox Name="ApplicationList" ItemsSource="{Binding Path=ApplicationList}" Grid.Row="3" Grid.Column="1" Margin="5,0,0,10">
            <ListBox.ContextMenu>
                <ContextMenu>
                    <MenuItem Name="RemoveFromList" Header="Remove from list"/>
                </ContextMenu>
            </ListBox.ContextMenu>
        </ListBox>
        <Grid Grid.Column="0" Grid.Row="4" Grid.ColumnSpan="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
            </Grid.RowDefinitions>
            <Label Content="Save Logs:" Grid.Row="0" Grid.Column="0" HorizontalAlignment="Right"/>
            <ComboBox Name="ComboSaveLogs" Width="150" Margin="5,0,0,2" SelectedIndex="{Binding Path=SaveLogsIndex}" Grid.Row="0" Grid.Column="1" HorizontalAlignment="Left">
                <ComboBoxItem Content="Never"/>
                <ComboBoxItem Content="Only when there is an error"/>
                <ComboBoxItem Content="Always"/>
            </ComboBox>
            <Label Content="Create Checkpoint:" Grid.Row="1" Grid.Column="0" HorizontalAlignment="Right"/>
            <ComboBox Name="ComboCheckPoint" Width="150" Margin="5,2,0,0" SelectedIndex="{Binding Path=CreateCheckPointIndex}" Grid.Column="1" Grid.Row="1" HorizontalAlignment="Left">
                <ComboBoxItem Content="Never"/>
                <ComboBoxItem Content="Only when there is an error"/>
                <ComboBoxItem Content="Always"/>
            </ComboBox>
            <Button Name="StartBtn" Content="Start" Width="75" Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,4,0,0"/>
        </Grid>
    </Grid>
</Window>



'@
# Add assemblies
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

# Make window
$Window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$xaml.SelectNodes("//*[@Name]") | Foreach-Object { Set-Variable -Name (("Window" + "_" + $_.Name)) -Value $Window.FindName($_.Name) }

#region CreateClass
Add-Type -Language CSharp @'
using System.ComponentModel;
public class WindowClass : INotifyPropertyChanged
{
    private string privateComputerName;
    public string ComputerName
    {
        get { return privateComputerName; }
        set
        {
            privateComputerName = value;
            NotifyPropertyChanged("ComputerName");
        }
    }

    private string privateVMName;
    public string VMName
    {
        get { return privateVMName; }
        set
        {
            privateVMName = value;
            NotifyPropertyChanged("VMName");
        }
    }

    private string privateHyperVServerName;
    public string HyperVServerName
    {
        get { return privateHyperVServerName; }
        set
        {
            privateHyperVServerName = value;
            NotifyPropertyChanged("HyperVServerName");
        }
    }

    private bool privateHyperVServerAltCredsCheckbox;
    public bool HyperVServerAltCredsCheckbox
    {
        get { return privateHyperVServerAltCredsCheckbox; }
        set
        {
            privateHyperVServerAltCredsCheckbox = value;
            NotifyPropertyChanged("HyperVServerAltCredsCheckbox");
        }
    }

    private object privateApplicationGrid;
    public object ApplicationGrid
    {
        get { return privateApplicationGrid; }
        set
        {
            privateApplicationGrid = value;
            NotifyPropertyChanged("ApplicationGrid");
        }
    }

    private object privateApplicationList;
    public object ApplicationList
    {
        get { return privateApplicationList; }
        set
        {
            privateApplicationList = value;
            NotifyPropertyChanged("ApplicationList");
        }
    }

    private object privateHyperVCreds;
    public object HyperVCreds
    {
        get { return privateHyperVCreds; }
        set
        {
            privateHyperVCreds = value;
            NotifyPropertyChanged("HyperVCreds");
        }
    }

    private int privateSaveLogsIndex;
    public int SaveLogsIndex
    {
        get { return privateSaveLogsIndex; }
        set
        {
            privateSaveLogsIndex = value;
            NotifyPropertyChanged("SaveLogsIndex");
        }
    }

    private int privateCreateCheckPointIndex;
    public int CreateCheckPointIndex
    {
        get { return privateCreateCheckPointIndex; }
        set
        {
            privateCreateCheckPointIndex = value;
            NotifyPropertyChanged("CreateCheckPointIndex");
        }
    }

    public event PropertyChangedEventHandler PropertyChanged;
    private void NotifyPropertyChanged(string property)
    {
        if(PropertyChanged != null)
        {
            PropertyChanged(this, new PropertyChangedEventArgs(property));
        }
    }
}

'@

Add-Type -Language CSharp @'
using System.ComponentModel;
public class AppGridClass : INotifyPropertyChanged
{
    private string privateName;
    public string Name
    {
        get { return privateName; }
        set
        {
            privateName = value;
            NotifyPropertyChanged("Name");
        }
    }

    private string privateInstalled;
    public string Installed
    {
        get { return privateInstalled; }
        set
        {
            privateInstalled = value;
            NotifyPropertyChanged("Installed");
        }
    }

    private string privateRequired;
    public string Required
    {
        get { return privateRequired; }
        set
        {
            privateRequired = value;
            NotifyPropertyChanged("Required");
        }
    }

    private string privateLastEvaluated;
    public string LastEvaluated
    {
        get { return privateLastEvaluated; }
        set
        {
            privateLastEvaluated = value;
            NotifyPropertyChanged("LastEvaluated");
        }
    }

    public event PropertyChangedEventHandler PropertyChanged;
    private void NotifyPropertyChanged(string property)
    {
        if(PropertyChanged != null)
        {
            PropertyChanged(this, new PropertyChangedEventArgs(property));
        }
    }
}

'@
#endregion

$WindowDataContext = New-Object -TypeName WindowClass
$WindowDataContext.ApplicationGrid = New-Object System.Collections.ArrayList
$WindowDataContext.ApplicationList = @()
$Window.DataContext = $WindowDataContext

$Window_LoadApplications.Add_Click({
    LoadApplications -CompName $WindowDataContext.ComputerName -WindowDataContext $WindowDataContext
})

$Window_RemoveFromList.Add_Click({
    $SelectedItems = $Window_ApplicationList.SelectedItems
    $tempAppArray = $Window_ApplicationList.Items
    $tempNewArray = @()
    Foreach ($instance in $tempAppArray) {
        $AddItem = $true
        foreach ($item in $SelectedItems) {
            if ($item -eq $instance) { $AddItem = $false }
        }
        if ($AddItem) { $tempNewArray += @($instance) }
    }
    $WindowDataContext.ApplicationList = $tempNewArray
})

$Window_AddToList.Add_Click({
    $SelectedItems = $Window_ApplicationGrid.SelectedItems
    Foreach ($Item in $SelectedItems) {
        $AddToArray = $true
        Foreach ($instance in $Window_ApplicationList.Items) {
            If ($instance -eq $Item.Name) { $AddToArray = $false }
        }
        If ($AddToArray) { $WindowDataContext.ApplicationList += $Item.Name }
    }
})

$Window_StartBtn.Add_Click({
    $Message = "Do you want to install these apps on the VM?`nNote, if you click yes the UI will go away and you can track progress in the log file and console window`n"
    Foreach ($instance in $WindowDataContext.ApplicationList) {
        $Message = $Message + "`n" + $instance
    }
    $Answer = $Popup.Popup($Message,0,"Are you sure?",1)
    if ($Answer -eq 1) {
        If ($WindowDataContext.HyperVServerAltCredsCheckbox) {
            $WindowDataContext.HyperVCreds = New-PSSession -Credential (Get-Credential -Message 'Please enter the Hyper-V credentials in the form of Domain\Username') -ComputerName $WindowDataContext.HyperVServerName
        }
        elseif ([string]::IsNullOrEmpty($WindowDataContext.HyperVServerName)) { $WindowDataContext.HyperVCreds = New-PSSession -ComputerName $WindowDataContext.HyperVServerName }
        $ContinueScript = $true
        try {
            $GetVMParams = @{}
            $GetVMParams.ScriptBlock = { (Get-VM -Name $args[0]).State }
            $GetVMParams.ArgumentList = $WindowDataContext.VMName
            If ($WindowDataContext.HyperVServerAltCredsCheckbox) { $GetVMParams.Session = $WindowDataContext.HyperVCreds }
            else { $GetVMParams.ComputerName = $WindowDataContext.HyperVServerName }
            $VMObject =  Invoke-Command @GetVMParams
            if ($VMObject -eq $null) {
                $ContinueScript = $false
            }
        }
        catch {
            $Popup.Popup("Could not find $strVMName",0,"Error!",16)
        }
        If ($ContinueScript) {
            $null = $Window.Close()
        }
    }
})

$Window.ShowDialog() | Out-Null
Read-Host
Try { Checkpoint-VM -Name $WindowDataContext.VMName -SnapshotName "TestAppScript-Original" }
catch { 
    Log -Message "Could not create VM checkpoint" -ErrorMessage $_.Exception.Message -LogFile $LogFile
    Exit
}

Log -Message "Successfully created checkpoint TestAppScript-Original" -LogFile $LogFile
Log -Message "Starting install of applications" -LogFile $LogFile

foreach ($instance in $WindowDataContext.ApplicationList) {
    
    Log "Installing $instance" -LogFile $LogFile
    $MakeCheckPoint = $false
    $CopyLogFiles = $false
    $StopLoop = $false
    Do {
        $VMObject = Get-VM -Name $WindowDataContext.VMName
        If ($VMObject.State -eq "Running") {
            Start-Sleep 10
            $StopLoop = $true
        }
        else { 
            Start-Sleep 10
            $Count++
            If ($Count -gt 10) { 
                Log -Message "Cannot restart VM!" -ErrorMessage "Error" -LogFile $LogFile
                Exit
            }
        }
    } while ($StopLoop -ne $true)
	
    $AppErrorCodes = 8,16,17,18,19,21,24,25, 4
    $AppInProgressCodes = 0,3,5,6,7,10,11,12,15,20,22,23,26,27,28
    $AppSuccessfulCodes = 1,2
    $AppRestartCodes = 13,14,9

    Try {
		$WMIPath = "\\" + $WindowDataContext.ComputerName + "\root\ccm\clientsdk:CCM_Application"
		$WMIClass = [WMIClass] $WMIPath
        $ApplicationID = ""
        $ApplicationRevision = ""
        $IsMachineTarget = ""
		Get-WmiObject -ComputerName $WindowDataContext.ComputerName -Query "select * from CCM_Application" -Namespace root\ccm\ClientSDK | ForEach-Object {
			if ($_.Name -eq $instance) {
				$ApplicationRevision = $_.Revision
				$IsMachineTarget = $_.IsMachineTarget
				$EnforcePreference = $_.EnforcePreference
				$ApplicationID = $_.ID
			}
		}
		$WMIClass.Install($ApplicationID, $ApplicationRevision, $IsMachineTarget, "", "1", $false) | Out-null
        
        $EndLoop = $false
        do {
            $InstallState = "NotInstalled"
		    Get-WmiObject -ComputerName $WindowDataContext.ComputerName -Query "select * from CCM_Application" -Namespace root\ccm\ClientSDK | ForEach-Object {
			    if ($_.Name -eq $instance) {
				    $InstallState = $_.InstallState
                    $EvaluationState = $_.EvaluationState
			    }
		    }
            $TranslatedEvaluationState = Translate-EvaluationState -EvaluationState $EvaluationState
            $CopyLogFiles = $false
            $MakeCheckPoint = $false
            If ($InstallState -eq "Installed") {
                if ($WindowDataContext.SaveLogsIndex -eq 2) { $CopyLogFiles = $true }
                if ($WindowDataContext.CreateCheckPointIndex -eq 2) { $MakeCheckPoint = $true }
                $EndLoop = $true
                Log "$instance - Successfully installed. Evaluation State: $TranslatedEvaluationState" -LogFile $LogFile
            }
            else {
                If ($AppErrorCodes -contains $EvaluationState) {
                    Log "$instance - Error installing application" -ErrorMessage $TranslatedEvaluationState -LogFile $LogFile
                    if ($WindowDataContext.SaveLogsIndex -ne 0) { $CopyLogFiles = $true }
                    if ($WindowDataContext.CreateCheckPointIndex -ne 0)  { $MakeCheckPoint = $true }
                    $EndLoop = $true
                }
                elseif ($AppInProgressCodes -contains $EvaluationState) {
                    Log "$instance - Still in progress. Sleeping 30 seconds. Evaluation State: $TranslatedEvaluationState" -LogFile $LogFile
                    Start-Sleep 30
                }
                elseif ($AppRestartCodes -contains $EvaluationState) {
                    Log "$instance - Requires restart to complete install. Will restart computer and wait 180 seconds now... Evaluation State: $TranslatedEvaluationState" -LogFile $LogFile
                    try {
                        shutdown /r /t 0 /m "\\$Script:strCompName"
                        Start-Sleep 180
                    }
                    catch { Log "$instance - Error restarting computer!" -ErrorMessage $_.Exception.Message -LogFile $LogFile }
                    try {
                        Log "$instance - Starting CCMExec service so the Application install can restart" -LogFile $LogFile
                        (Get-WmiObject -ComputerName $WindowDataContext.ComputerName -Query "Select * From Win32_Service where Name like 'ccmexec'").StartService()
                        Start-Sleep 60
                    }
                    catch { Log "$instance - Error starting ccmexec on remote computer" -ErrorMessage $_.Exception.Message -LogFile $LogFile }
                    try {
                        Log "$instance - Triggering application install again to re-check detection method..." -LogFile $LogFile
                        $WMIPath = "\\" + $WindowDataContext.ComputerName + "\root\ccm\clientsdk:CCM_Application"
		                $WMIClass = [WMIClass] $WMIPath
                        $ApplicationID = ""
                        $ApplicationRevision = ""
                        $IsMachineTarget = ""
		                Get-WmiObject -ComputerName $WindowDataContext.ComputerName -Query "select * from CCM_Application" -Namespace root\ccm\ClientSDK | ForEach-Object {
			                if ($_.Name -eq $instance) {
				                $ApplicationRevision = $_.Revision
				                $IsMachineTarget = $_.IsMachineTarget
				                $EnforcePreference = $_.EnforcePreference
				                $ApplicationID = $_.ID
			                }
		                }
		                $WMIClass.Install($ApplicationID, $ApplicationRevision, $IsMachineTarget, "", "1", $false) | Out-null
                        Start-Sleep 20
                    }
                    catch { 
                        Log "$instance - Error triggering application install" -ErrorMessage $_.Exception.Message -LogFile $LogFile
                        if ($WindowDataContext.SaveLogsIndex -ne 0) { $CopyLogFiles = $true }
                        if ($WindowDataContext.CreateCheckPointIndex -ne 0)  { $MakeCheckPoint = $true }
                        $EndLoop = $true
                    }
                }
                elseif ($AppSuccessfulCodes -contains $EvaluationState) {
                    if ($WindowDataContext.SaveLogsIndex -eq 2) { $CopyLogFiles = $true }
                    if ($WindowDataContext.CreateCheckPointIndex -eq 2) { $MakeCheckPoint = $true }
                    $EndLoop = $true
                    Log "$instance - Successfully installed. Evaluation State: $TranslatedEvaluationState" -LogFile $LogFile
                }
            }
        } while ($EndLoop -ne $true)
	}
	Catch { 
        Log -Message "Error installing $AppName -" -ErrorMessage $_.Exception.Message -LogFile $LogFile
        if ($WindowDataContext.SaveLogsIndex -ne 0) { $CopyLogFiles = $true }
        if ($WindowDataContext.CreateCheckPointIndex -ne 0)  { $MakeCheckPoint = $true }
    }
    
    If ($MakeCheckPoint) {
        Try {
            Log -Message "$instance - Creating checkpoint" -LogFile $LogFile
            $CheckpointName = "App-" + $instance
            Checkpoint-VM -Name $WindowDataContext.VMName -SnapshotName $CheckpointName
            Log -Message "$instance - Created checkpoint!" -LogFile $LogFile
        }
        catch { Log -Message "$instance - Error creating checkpoint" -ErrorMessage $_.Exception.Message -LogFile $LogFile }
    }
    
    if ($CopyLogFiles) {
        Try {
            $AppLogDirectory = "$Directory\Logs\$instance"
            Log -Message "Saving $instance log files to $AppLogDirectory" -LogFile $LogFile
            $CopyPath = "\\" + $WindowDataContext.ComputerName + "\c$\windows\ccm\logs"
            Copy-Item $CopyPath $AppLogDirectory -Recurse -Force
        }
        catch { Log -Message "$instance - Error copying log files!" -ErrorMessage $_.Exception.Message -LogFile $LogFile }
    }

    Try {
        Log -Message "Reverting VM to previous checkpoint" -LogFile $LogFile
        Restore-VMSnapshot -VMName $WindowDataContext.VMName -Name "TestAppScript-Original" -Confirm:$false
        Start-Sleep 10
    }
    catch {
        Log -Message "Error reverting to previous checkpoint!" -ErrorMessage $_.Exception.Message -LogFile $LogFile
        exit
    }
}

Log -Message "Finished!" -Type 2 -LogFile $LogFile
