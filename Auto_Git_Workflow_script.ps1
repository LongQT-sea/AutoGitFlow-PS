#Requires -Version 5.1
<#
.SYNOPSIS
    Auto Git Workflow Script
.DESCRIPTION
    Automates common Git operations with improved error handling, logging, and user experience.
    Features include smart repository detection, automated commits, remote synchronization, and more.
.AUTHOR
    github.com/LongQT-sea
.VERSION
    v0.2.0
#>
[CmdletBinding()]
param(
    [switch]$Verbose,
    [switch]$SkipInternet,
    [string]$LogLevel = "Info"
)
# Script configuration
$script:Config = @{
    MaxDirectorySize = 3GB
    CommitMessageTemplate = "Update {0:yyyy-MM-dd HH:mm}"
    DefaultBranch = "main"
    MaxStatusLines = 25
    MaxCommitDisplay = 5
    GitIgnoreDefaults = @("", "*.lnk", ".env", ".env.production", ".DS_Store", "desktop.ini")
}
# Initialize required assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Net
#
#
#Main Workflow
function Main {
    Write-Section "Git Workflow Automation"
    Write-Log "Starting Git workflow automation..." -Level Info
    
    # Step 1: Ensure Git is available
    if (-not (Test-GitInstalled)) {
        if (-not (Install-Git)) {
            return
        }
    }
    
    # Step 2: Ensure we're in a Git repository
    if (-not (Test-GitRepository)) {
        Write-Log "Not in a Git repository" -Level Warning
        if (-not (Initialize-Repository)) {
            Write-Log "Repository setup cancelled or failed" -Level Warning
            return
        }
    }
    
    Write-Log "Repository check passed" -Level Success
    
    # Step 3: Get current status and decide on actions
    $status = Get-GitStatus
    
    if ($status.HasChanges) {
        Write-Section "Local Changes Detected"
        Write-Log "Found $($status.Changes.Count) local changes" -Level Info
        
        $commitSuccess = Invoke-CommitChanges
        
        if ($commitSuccess) {
            Write-Log "Changes committed successfully" -Level Success
            Sync-WithRemote
        }
    } else {
        Write-Section "No Local Changes"
        Write-Log "Working tree is clean" -Level Success
        Show-GitStatus
        Sync-WithRemote
    }
    
    Write-Section "Workflow Complete"
    Write-Log "Git workflow automation completed" -Level Success
}
#
#region Logging Functions
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success", "Debug")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "Info" { "White" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        "Success" { "Green" }
        "Debug" { "Gray" }
    }
    
    if ($Level -ne "Debug" -or $script:Config.LogLevel -eq "Debug") {
        Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
    }
}
function Write-Section {
    param([string]$Title)
    Write-Host "`n$('=' * 60)" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "$('=' * 60)" -ForegroundColor Cyan
}
#endregion
#
#
#region UI Helper Functions
function Show-Message {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Title = "Git Workflow",
        [ValidateSet("None", "Information", "Warning", "Error", "Question")]
        [string]$Icon = "None"
    )
    
    $iconEnum = switch ($Icon) {
        'Error' { [System.Windows.MessageBoxImage]::Error }
        'Warning' { [System.Windows.MessageBoxImage]::Warning }
        'Information' { [System.Windows.MessageBoxImage]::Information }
        'Question' { [System.Windows.MessageBoxImage]::Question }
        default { [System.Windows.MessageBoxImage]::None }
    }
    
    [void][System.Windows.MessageBox]::Show($Message, $Title, [System.Windows.MessageBoxButton]::OK, $iconEnum)
}
function Confirm-Action {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Title = "Git Workflow",
        [System.Windows.MessageBoxButton]$Buttons = [System.Windows.MessageBoxButton]::YesNo
    )
    
    $result = [System.Windows.MessageBox]::Show($Message, $Title, $Buttons, [System.Windows.MessageBoxImage]::Question)
    return $result
}
function Get-UserInput {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [string]$DefaultValue = "",
        [string]$Title = "Git Workflow",
        [switch]$Multiline
    )
    
    $xaml = if ($Multiline) {
        @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title" SizeToContent="Height" Width="500" MinHeight="200"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResize">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="$Prompt" Margin="0,0,0,15" FontSize="14" TextWrapping="Wrap"/>
        <TextBox x:Name="InputTextBox" Grid.Row="1" MinHeight="80" Padding="8" FontSize="12" 
                 AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" 
                 Text="$DefaultValue"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,15,0,0">
            <Button x:Name="OKButton" Content="OK" Width="80" Height="35" Margin="0,0,10,0" 
                    Background="#0078D4" Foreground="White" IsDefault="True"/>
            <Button x:Name="CancelButton" Content="Cancel" Width="80" Height="35" 
                    Background="#E1E1E1" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@
    } else {
        @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title" SizeToContent="Height" Width="450" MinHeight="180"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="$Prompt" Margin="0,0,0,15" FontSize="14" TextWrapping="Wrap"/>
        <TextBox x:Name="InputTextBox" Grid.Row="1" Height="35" Padding="8" FontSize="12" 
                 VerticalContentAlignment="Center" Text="$DefaultValue"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,15,0,0">
            <Button x:Name="OKButton" Content="OK" Width="80" Height="35" Margin="0,0,10,0" 
                    Background="#0078D4" Foreground="White" IsDefault="True"/>
            <Button x:Name="CancelButton" Content="Cancel" Width="80" Height="35" 
                    Background="#E1E1E1" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@
    }
    
    try {
        $window = [System.Windows.Markup.XamlReader]::Parse($xaml)
        $inputTextBox = $window.FindName("InputTextBox")
        $okButton = $window.FindName("OKButton")
        $cancelButton = $window.FindName("CancelButton")
        
        $result = $null
        
        $okButton.Add_Click({
            $script:result = $inputTextBox.Text
            $window.DialogResult = $true
            $window.Close()
        })
        
        $cancelButton.Add_Click({
            $script:result = $null
            $window.DialogResult = $false
            $window.Close()
        })
        
        $inputTextBox.Add_Loaded({
            $inputTextBox.Focus()
            $inputTextBox.SelectAll()
        })
        
        $inputTextBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return' -and -not $Multiline) {
                $okButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            }
        })
        
        $dialogResult = $window.ShowDialog()
        return $(if ($dialogResult) { $script:result } else { $null })
    }
    catch {
        Write-Log "XAML dialog failed, using fallback input: $($_.Exception.Message)" -Level Warning
        Write-Host "$Prompt " -NoNewline -ForegroundColor Cyan
        if ($DefaultValue) { Write-Host "[$DefaultValue]: " -NoNewline -ForegroundColor Gray }
        $input = Read-Host
        return if ([string]::IsNullOrWhiteSpace($input)) { $DefaultValue } else { $input }
    }
}
#endregion
#
#
#region Git Helper Functions
function Test-GitInstalled {
    try {
        $gitVersion = git --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Git detected: $gitVersion" -Level Success
            return $true
        }
    }
    catch { }
    
    Write-Log "Git not found in PATH" -Level Warning
    return $false
}
function Install-Git {
    # First check if user wants to install Git
    $confirmResult = Confirm-Action "Git is not installed. Would you like to install it using winget?"
    if ($confirmResult -ne "Yes") {
        Write-Log "Git installation cancelled by user" -Level Info
        return $false
    }
    
    # Check internet connection
    if (-not (Test-InternetConnection)) {
        Show-Message "An internet connection is required to install Git." "Git Error" "Error"
        return $false
    }
    
    # Ensure Winget is available
    while (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Start-Process "ms-windows-store://pdp?hl=en-us&gl=us&productid=9nblggh4nns1"
        Start-Sleep 3 # Give Store time to open
        Show-Message "The 'winget' command is unavailable.`nPlease update 'App Installer' via Microsoft Store.`n`nClick OK to continue after 'App Installer' is updated"
    }
    
    Write-Log "Updating winget sources..."
    # Suppress output of winget source update from being captured as the function's return value.
    winget source update --disable-interactivity | Out-Null 
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to update Winget sources: $($_.Exception.Message)" -Level Error
        return $false
    }
    
    Write-Log "Installing Git using Winget..."
    # Suppress any success stream output from winget install.
    # Winget's progress bar writes to the host, not the success stream, so this primarily
    # catches any final summary lines that might otherwise become the function's return value.
    $null = winget install --id=Git.Git --accept-package-agreements --accept-source-agreements --disable-interactivity --scope user
    
    # Verify installation by checking common paths
    if ((Test-Path "${env:ProgramFiles}\Git\cmd\git.exe") -or (Test-Path "${env:LOCALAPPDATA}\Programs\Git\bin\git.exe")) {
        Write-Log "Git installed successfully!" -Level Success
        # Git might not be available in the current session's PATH
        # Return $false to signal to Main that the current session is not ready and script execution should halt for this run.
        return $false
    } else {
        Show-Message "Git installation failed. Please install manually from git-scm.com" "Installation Error" "Error"
        return $false
    }
}
function Test-GitRepository {
    try {
        git rev-parse --is-inside-work-tree 2>$null | Out-Null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}
function Test-InternetConnection {
    if ($SkipInternet) {
        Write-Log "Skipping internet connection test (SkipInternet flag)" -Level Debug
        return $true
    }
    
    # Test 1: Basic TCP connectivity to Cloudflare
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $connectResult = $tcp.BeginConnect("1.1.1.1", 443, $null, $null)
        $waitHandle = $connectResult.AsyncWaitHandle
        try {
            if (-not $waitHandle.WaitOne(2000, $false)) {
                # Timeout occurred
                $tcp.Close()
                throw "Timeout connecting to 1.1.1.1:443"
            }
            # Connection successful or failed quickly
            $tcp.EndConnect($connectResult)
        } finally {
            $waitHandle.Close()
            $tcp.Close() # Ensure closed even if EndConnect throws
        }
        Write-Log "Internet connectivity confirmed via 1.1.1.1:443" -Level Debug
    } catch {
        Write-Log "Internet connectivity test failed: $($_.Exception.Message)" -Level Warning
        return $false
    }
    
    # Test 2: DNS resolution for Git services
    $dnsTests = @("github.com", "gitlab.com", "bitbucket.org")
    $dnsFailures = @()
    
    foreach ($hostname in $dnsTests) {
        try {
            [System.Net.Dns]::GetHostEntry($hostname) | Out-Null
            Write-Log "DNS resolution successful for $hostname" -Level Debug
        } catch {
            $dnsFailures += $hostname
            Write-Log "DNS resolution failed for $hostname" -Level Debug
        }
    }
    
    # Check if all DNS tests failed
    if ($dnsFailures.Count -eq $dnsTests.Count) {
        Write-Log "DNS resolution failed for all Git services: $($dnsFailures -join ', ')" -Level Warning
        Show-Message "Failed to resolve DNS for Git services. Cannot continue." "DNS Error" "Warning"
        return $false
    } elseif ($dnsFailures.Count -gt 0) {
        Write-Log "DNS resolution failed for some services: $($dnsFailures -join ', '), but continuing..." -Level Warning
    }
    
    Write-Log "Internet connectivity test passed" -Level Debug
    return $true
}
function Test-Email {
    param([string]$Email)
    return $Email -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
}
function Initialize-GitConfig {
    Write-Log "Checking Git configuration..."
    
    $userName = git config --global user.name 2>$null
    $userEmail = git config --global user.email 2>$null
    
    # Get user name
    while ([string]::IsNullOrWhiteSpace($userName)) {
        $userName = Get-UserInput "Enter your Git username for commits:" -Title "Git Configuration"
        if ($userName -eq $null) {
            Write-Log "Git configuration cancelled by user" -Level Warning
            return $false
        }
    }
    
    # Get user email
    while (-not (Test-Email $userEmail)) {
        if (![string]::IsNullOrWhiteSpace($userEmail)) {
            Show-Message "Invalid email format. Please enter a valid email address." "Invalid Email" "Warning"
        }
        $userEmail = Get-UserInput "Enter your Git email for commits:" -Title "Git Configuration"
        if ($userEmail -eq $null) {
            Write-Log "Git configuration cancelled by user" -Level Warning
            return $false
        }
    }
    
    # Set configuration
    try {
        if ($userName -ne (git config --global user.name 2>$null)) {
            git config --global user.name $userName
            Write-Log "Set Git username: $userName" -Level Success
        }
        
        if ($userEmail -ne (git config --global user.email 2>$null)) {
            git config --global user.email $userEmail
            Write-Log "Set Git email: $userEmail" -Level Success
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to set Git configuration: $($_.Exception.Message)" -Level Error
        return $false
    }
}
#endregion
#
#
#region Repository Management
function Initialize-Repository {
    $action = Show-RepositoryOptions
    
    switch ($action) {
        "Init" {
            return New-GitRepository
        }
        "Clone" {
            return Invoke-GitClone
        }
        default {
            Write-Log "Repository initialization cancelled" -Level Warning
            return $false
        }
    }
}
function Show-RepositoryOptions {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Git Repository Setup" SizeToContent="Height" Width="480"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
    <Grid Margin="25">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" FontSize="16" FontWeight="Bold" Margin="0,0,0,10">
            Git Repository Setup
        </TextBlock>
        
        <TextBlock Grid.Row="1" TextWrapping="Wrap" Margin="0,0,0,25" FontSize="13">
            This directory is not a Git repository. Choose an option:
        </TextBlock>
        
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="InitButton" Content="Initialize New Repository" 
                    Width="160" Height="35" Margin="0,0,10,0" 
                    Background="#28a745" Foreground="White"/>
            <Button x:Name="CloneButton" Content="Clone Remote Repository" 
                    Width="160" Height="35" Margin="0,0,10,0" 
                    Background="#007bff" Foreground="White"/>
            <Button x:Name="CancelButton" Content="Cancel" 
                    Width="80" Height="35" Background="#6c757d" Foreground="White"/>
        </StackPanel>
    </Grid>
</Window>
"@
    
    try {
        $window = [System.Windows.Markup.XamlReader]::Parse($xaml)
        $result = $null
        
        $window.FindName("InitButton").Add_Click({ $script:result = "Init"; $window.Close() })
        $window.FindName("CloneButton").Add_Click({ $script:result = "Clone"; $window.Close() })
        $window.FindName("CancelButton").Add_Click({ $script:result = $null; $window.Close() })
        
        $window.ShowDialog() | Out-Null
        return $script:result
    }
    catch {
        Write-Log "UI error, using console fallback: $($_.Exception.Message)" -Level Warning
        
        Write-Host "`nRepository Options:" -ForegroundColor Cyan
        Write-Host "1. Initialize new repository"
        Write-Host "2. Clone remote repository"
        Write-Host "3. Cancel"
        
        do {
            $choice = Read-Host "`nEnter choice (1-3)"
        } while ($choice -notin @("1", "2", "3"))
        
        switch ($choice) {
            "1" { return "Init" }
            "2" { return "Clone" }
            default { return $null }
        }
    }
}
function New-GitRepository {
    # Check directory size
    $currentSize = Get-DirectorySize -Path "."
    if ($currentSize -gt $script:Config.MaxDirectorySize) {
        $sizeGB = [math]::Round($currentSize / 1GB, 2)
        $message = "Directory size is ${sizeGB}GB, which exceeds the recommended 3GB limit.`n`nThis may cause performance issues. Continue anyway?"
        
        $confirmResult = Confirm-Action $message "Large Directory Warning"
        if ($confirmResult -ne "Yes") {
            Write-Log "Repository initialization cancelled due to large directory size" -Level Warning
            return $false
        }
    }
    
    try {
        Write-Log "Initializing new Git repository..."
        git init -b $script:Config.DefaultBranch 2>$null
        
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path ".git")) {
            throw "Git init command failed"
        }
        
        # Create .gitignore
        $script:Config.GitIgnoreDefaults | Out-File .gitignore -Encoding utf8
        
        # Handle potential ownership issues
        try {
            git add .gitignore 2>$null
            if ($LASTEXITCODE -ne 0) {
                $currentPath = Get-Location
                git config --global --add safe.directory $currentPath
                Write-Log "Added current directory to Git safe.directory config" -Level Info
                git add .gitignore
            }
        }
        catch {
            Write-Log "Warning: Could not add .gitignore file: $($_.Exception.Message)" -Level Warning
        }
        
        git commit -m "Initial commit with .gitignore" 2>$null
        git config core.safecrlf false
        
        Write-Log "Successfully initialized Git repository with branch '$($script:Config.DefaultBranch)'" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to initialize Git repository: $($_.Exception.Message)" -Level Error
        return $false
    }
}
function Invoke-GitClone {
    if (-not (Test-InternetConnection)) {
        Show-Message "Internet connection required for cloning repositories." "Connection Error" "Error"
        return $false
    }
    
    $remoteUrl = Get-UserInput "Enter the repository URL to clone:" -Title "Clone Repository"
    if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
        Write-Log "Clone cancelled: No URL provided" -Level Warning
        return $false
    }
    
    # Validate URL format
    if ($remoteUrl -notmatch '^(https?://|git@)') {
        Show-Message "Invalid repository URL format. Must start with http://, https://, or git@" "Invalid URL" "Error"
        return $false
    }
    
    $useShallow = (Confirm-Action "Use shallow clone (faster, but limited history)?") -eq "Yes"
    
    try {
        Write-Log "Cloning repository: $remoteUrl"
        
        $cloneArgs = @("clone")
        if ($useShallow) { $cloneArgs += "--depth=1" }
        $cloneArgs += $remoteUrl
        
        & git @cloneArgs
        
        if ($LASTEXITCODE -eq 0) {
            # Extract repository name and change directory
            $repoName = [System.IO.Path]::GetFileNameWithoutExtension($remoteUrl.Split('/')[-1])
            if (Test-Path $repoName) {
                Set-Location $repoName
                Write-Log "Successfully cloned and entered directory: $repoName" -Level Success
                return $true
            }
        }
        
        throw "Clone command failed with exit code: $LASTEXITCODE"
    }
    catch {
        Write-Log "Failed to clone repository: $($_.Exception.Message)" -Level Error
        return $false
    }
}
function Get-DirectorySize {
    param([string]$Path)
    try {
        return (Get-ChildItem $Path -Recurse -Force -File | Measure-Object -Property Length -Sum).Sum
    }
    catch {
        return 0
    }
}
#endregion
#
#
#region Git Operations
function Get-GitStatus {
    if (-not (Test-GitRepository)) {
        Write-Log "Not in a Git repository" -Level Warning
        return $null
    }
    
    try {
        $branch = git branch --show-current 2>$null
        $remote = git remote get-url origin 2>$null
        
        $status = @{
            Branch = $branch
            Remote = $remote
            HasChanges = $false
            Changes = @()
            DisplayChanges = ""
            Commits = @()
        }
        
        # Check for changes
        $porcelain = git status --porcelain 2>$null
        if ($porcelain) {
            # Store individual changes as array (for counting)
            $status.Changes = $porcelain -split "`n" | Where-Object { $_ }
            $status.HasChanges = $true
            
            # Get the more verbose status for display
            $gitStatusOutput = git -c status.relativePaths=false status | Out-String
            $lines = $gitStatusOutput -split "`r?`n"
            $maxLinesToShow = 20
            
            if ($lines.Count -gt $maxLinesToShow) {
                $status.DisplayChanges = ($lines | Select-Object -First $maxLinesToShow) -join "`n"
                $status.DisplayChanges += "`n`n...(Status truncated, run 'git status' for full details)...`n`n"
            } else {
                $status.DisplayChanges = $gitStatusOutput
            }
        }
        
        # Get recent commits
        $commits = git log -5 --pretty=format:"%h - %s (%cr)" 2>$null
        if ($commits) {
            $status.Commits = $commits -split "`n"
        }
        
        return $status
    }
    catch {
        Write-Log "Error getting Git status: $($_.Exception.Message)" -Level Error
        return $null
    }
}
function Show-GitStatus {
    $status = Get-GitStatus
    if (-not $status) { return }
    
    $message = "Branch: $($status.Branch)`n"
    
    if ($status.Remote) {
        $message += "Remote: $($status.Remote)`n"
    } else {
        $message += "Remote: Not configured`n"
    }
    
    $message += "`n"
    
    if ($status.HasChanges) {
        $message += "Changes detected ($($status.Changes.Count) files):`n`n"
        $message += $status.DisplayChanges
    } else {
        $message += "Working tree clean"
    }
    
    if ($status.Commits) {
        $message += "`n`nRecent commits:`n"
        $message += ($status.Commits -join "`n")
    }
    
    Show-Message $message "Git Status"
}
function Invoke-CommitChanges {
    if (-not (Initialize-GitConfig)) {
        return $false
    }
    
    $status = Get-GitStatus
    if (-not $status.HasChanges) {
        Write-Log "No changes to commit" -Level Info
        return $false
    }
    
    $message = @"
Found $($status.Changes.Count) file(s) with changes:`n
$($status.DisplayChanges)
What would you like to do?
- Yes:      Stage and commit all changes
- No:       Stage changes only
- Cancel:   Do nothing
"@
    
    $result = Confirm-Action $message "Commit Changes" ([System.Windows.MessageBoxButton]::YesNoCancel)
    
    switch ($result) {
        "Yes" {
            return Complete-Commit
        }
        "No" {
            # Stage only
            Write-Log "Staging changes only..."
            git add . 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Changes staged successfully" -Level Success
            } else {
                Write-Log "Failed to stage changes" -Level Error
            }
            return $false
        }
        default {
            Write-Log "Commit operation cancelled" -Level Info
            return $false
        }
    }
}
function Complete-Commit {
    try {
        Write-Log "Staging all changes..."
        git add . 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to stage changes"
        }
        
        # Check if anything was staged
        git diff --staged --quiet 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "No changes were effectively staged" -Level Warning
            return $false
        }
        
        # Get commit message
        $defaultMessage = $script:Config.CommitMessageTemplate -f (Get-Date)
        $commitMessage = Get-UserInput "Enter commit message:" -DefaultValue $defaultMessage -Title "Commit Message"
        
        if ($commitMessage -eq $null) {
            Write-Log "Commit cancelled by user" -Level Warning
            return $false
        }
        
        if ([string]::IsNullOrWhiteSpace($commitMessage)) {
            $commitMessage = $defaultMessage
        }
        
        Write-Log "Committing changes..."
        git commit -m $commitMessage 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Changes committed successfully: $commitMessage" -Level Success
            return $true
        } else {
            throw "Commit command failed"
        }
    }
    catch {
        Write-Log "Failed to commit changes: $($_.Exception.Message)" -Level Error
        return $false
    }
}
function Sync-WithRemote {
    if (-not (Test-InternetConnection)) {
        Write-Log "Internet connection required for remote operations" -Level Warning
        return
    }
    
    $remote = git remote get-url origin 2>$null
    
    if (-not $remote) {
        Setup-Remote
        return
    }
    
    Write-Log "Syncing with remote: $remote"
    
    # Fetch latest changes
    git fetch origin 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to fetch from remote" -Level Error
        return
    }
    
    $syncStatus = Get-RemoteSyncStatus
    
    switch ($syncStatus) {
        "UpToDate" {
            Write-Log "Repository is up to date with remote" -Level Success
            Check-UnpushedCommits
        }
        "Behind" {
            Handle-PullRequired
        }
        "Ahead" {
            Handle-PushRequired
        }
        "Diverged" {
            Handle-Divergence
        }
        default {
            Write-Log "Could not determine sync status" -Level Warning
        }
    }
}
function Get-RemoteSyncStatus {
    try {
        $local = git rev-parse "@" 2>$null
        $remote = git rev-parse "@{u}" 2>$null
        $base = git merge-base "@" "@{u}" 2>$null
        
        if ($local -eq $remote) {
            return "UpToDate"
        } elseif ($local -eq $base) {
            return "Behind"
        } elseif ($remote -eq $base) {
            return "Ahead"
        } else {
            return "Diverged"
        }
    }
    catch {
        return "Unknown"
    }
}
function Handle-PullRequired {
    if (Test-SkipPrompt "pull_changes") {
        Write-Log "Skipping pull changes based on user preference" -Level Info
        return
    }
    
    $message = "Your branch is behind the remote. Pull changes now?`n`nYes - Pull now`nNo - Skip for now`nCancel - Don't ask again for this repository"
    $result = Confirm-Action $message "Pull Remote Changes" ([System.Windows.MessageBoxButton]::YesNoCancel)
    
    switch ($result) {
        "Yes" {
            Write-Log "Pulling changes from remote..."
            git pull 2>$null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Successfully pulled changes from remote" -Level Success
            } else {
                Write-Log "Failed to pull changes. Check for conflicts." -Level Error
            }
        }
        "No" {
            Write-Log "Pull operation skipped by user" -Level Info
        }
        "Cancel" {
            Set-SkipPrompt "pull_changes"
            Write-Log "Set preference to skip pull prompts for this repository" -Level Info
        }
    }
}
function Handle-PushRequired {
    if (Test-SkipPrompt "push_changes") {
        Write-Log "Skipping push changes based on user preference" -Level Info
        return
    }
    
    $message = "Your branch is ahead of remote. Push changes now?`n`nYes - Push now`nNo - Skip for now`nCancel - Don't ask again for this repository"
    $result = Confirm-Action $message "Push Remote Changes" ([System.Windows.MessageBoxButton]::YesNoCancel)
    
    switch ($result) {
        "Yes" {
            Push-ToRemote
        }
        "No" {
            Write-Log "Push operation skipped by user" -Level Info
        }
        "Cancel" {
            Set-SkipPrompt "push_changes"
            Write-Log "Set preference to skip push prompts for this repository" -Level Info
        }
    }
}
function Handle-Divergence {
    $message = @"
🔀 Your branch has diverged from the remote.
This requires manual resolution. Options:
    
📥 1. Pull and Merge (recommended for beginners)
   git pull
   ✔ Keeps all commits, adds a merge commit
    
🔧 2. Pull and Rebase (clean history)
   git pull --rebase
   ✔ Reapplies your commits on top of remote changes
   ⚠ Avoid if already pushed
    
❗ 3. Force Push (danger!)
   git push --force
   ⚠ Overwrites remote branch with your local version
    
💡 Tip: Use option 1 if unsure.
"@
    
    Show-Message $message "Branch Diverged" "Warning"
}
function Push-ToRemote {
    try {
        $branch = git branch --show-current 2>$null
        Write-Log "Pushing to remote branch: $branch"
        
        git push -u origin $branch 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Successfully pushed changes to remote" -Level Success
        } else {
            throw "Push command failed"
        }
    }
    catch {
        Write-Log "Failed to push changes: $($_.Exception.Message)" -Level Error
        Show-Message "Failed to push changes. Check authentication and network connection." "Push Failed" "Error"
    }
}
function Check-UnpushedCommits {
    if (Test-SkipPrompt "unpushed_commits") {
        Write-Log "Skipping unpushed commits check based on user preference" -Level Info
        return
    }
    
    $unpushed = git log --branches --not --remotes --oneline 2>$null
    
    if ($unpushed) {
        $commits = $unpushed -split "`n" | Where-Object { $_ }
        $count = $commits.Count
        $display = ($commits | Select-Object -First $script:Config.MaxCommitDisplay) -join "`n"
        
        if ($count -gt $script:Config.MaxCommitDisplay) {
            $display += "`n... and $($count - $script:Config.MaxCommitDisplay) more commits"
        }
        
        $message = "You have $count unpushed commit(s):`n`n$display`n`nPush to remote now?`n`nYes - Push now`nNo - Skip for now`nCancel - Don't ask again for this repository"
        $result = Confirm-Action $message "Unpushed Commits" ([System.Windows.MessageBoxButton]::YesNoCancel)
        
        switch ($result) {
            "Yes" {
                Push-ToRemote
            }
            "No" {
                Write-Log "Push operation skipped by user" -Level Info  
            }
            "Cancel" {
                Set-SkipPrompt "unpushed_commits"
                Write-Log "Set preference to skip unpushed commits prompts for this repository" -Level Info
            }
        }
    }
}
function Setup-Remote {
    Write-Log "Setting up remote repository..."
    
    if (-not (Initialize-GitConfig)) {
        return
    }
    
    if (Test-SkipPrompt "git_remote") {
        Write-Log "Skipping remote setup based on user preference" -Level Info
        return
    }
    
    $message = "No remote repository configured.`n`nWould you like to add a remote repository URL?`n`n(This links your local repository to a remote service like GitHub, GitLab, etc.)`n`nYes - Add remote now`nNo - Skip for now`nCancel - Don't ask again for this repository"
    $result = Confirm-Action $message "Setup Remote Repository" ([System.Windows.MessageBoxButton]::YesNoCancel)
    
    switch ($result) {
        "Yes" {
            $remoteUrl = Get-UserInput "Enter the remote repository URL:" -Title "Remote Repository Setup"
            
            if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
                Write-Log "Remote setup cancelled: No URL provided" -Level Warning
                return
            }
            
            try {
                Write-Log "Adding remote 'origin': $remoteUrl"
                git remote add origin $remoteUrl 2>$null
                
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to add remote origin"
                }
                
                # Test connection and check if remote has branches
                Write-Log "Testing connection to remote..."
                $remoteBranches = git ls-remote --heads origin 2>$null
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Successfully connected to remote repository" -Level Success
                    
                    if ($remoteBranches) {
                        Write-Log "Remote has existing branches, pulling..."
                        git pull origin (git branch --show-current) 2>$null
                    } else {
                        Write-Log "Remote repository is empty" -Level Info
                    }
                } else {
                    Write-Log "Warning: Could not connect to remote repository" -Level Warning
                }
            }
            catch {
                Write-Log "Failed to setup remote: $($_.Exception.Message)" -Level Error
                Show-Message "Failed to add remote repository. Please check the URL and your network connection." "Remote Setup Failed" "Error"
            }
        }
        "No" {
            Write-Log "Remote setup skipped by user" -Level Info
        }
        "Cancel" {
            Set-SkipPrompt "git_remote"
            Write-Log "Set preference to skip remote setup prompts for this repository" -Level Info
        }
    }
}
#endregion
#
#
#region Preference Management
function Get-UserPreferences {
    $gitDir = git rev-parse --git-dir 2>$null
    if (-not $gitDir) { return @{} }
    
    $prefsFile = Join-Path $gitDir "workflow-prefs.json"
    
    if (Test-Path $prefsFile) {
        try {
            $jsonContent = Get-Content $prefsFile -Raw | ConvertFrom-Json
            $hashtable = @{}
            
            # Convert PSObject to hashtable for compatibility
            $jsonContent.PSObject.Properties | ForEach-Object {
                $hashtable[$_.Name] = $_.Value
            }
            
            return $hashtable
        }
        catch {
            Write-Log "Error reading preferences: $($_.Exception.Message)" -Level Warning
            return @{}
        }
    }
    
    return @{}
}
function Set-UserPreference {
    param(
        [string]$Key,
        [object]$Value
    )
    
    $gitDir = git rev-parse --git-dir 2>$null
    if (-not $gitDir) { return }
    
    $prefsFile = Join-Path $gitDir "workflow-prefs.json"
    $prefs = Get-UserPreferences
    
    $prefs[$Key] = $Value
    
    try {
        # Convert hashtable to PSObject for JSON serialization
        $psObject = New-Object PSObject
        $prefs.Keys | ForEach-Object {
            $psObject | Add-Member -Type NoteProperty -Name $_ -Value $prefs[$_]
        }
        
        $psObject | ConvertTo-Json -Depth 3 | Set-Content $prefsFile -Encoding UTF8
        Write-Log "Saved preference: $Key = $Value" -Level Debug
    }
    catch {
        Write-Log "Error saving preferences: $($_.Exception.Message)" -Level Warning
    }
}
function Test-SkipPrompt {
    param([string]$PromptType)
    
    $prefs = Get-UserPreferences
    return $prefs.ContainsKey("Skip_$PromptType") -and $prefs["Skip_$PromptType"]
}
function Set-SkipPrompt {
    param([string]$PromptType)
    
    Set-UserPreference "Skip_$PromptType" $true
    Write-Log "Set preference to skip '$PromptType' prompts in '.git\workflow-prefs.json'" -Level Info
}
#endregion
#
function Show-Help {
    $helpText = @"
Git Workflow Automation Script v2.0
DESCRIPTION:
    Automates common Git operations including repository initialization,
    change detection, committing, and remote synchronization.
PARAMETERS:
    -Verbose        Enable verbose logging
    -SkipInternet   Skip internet connectivity tests
    -LogLevel       Set logging level (Info, Warning, Error, Debug)
FEATURES:
    • Automatic Git installation via winget
    • Smart repository detection and initialization
    • User-friendly commit workflow
    • Remote repository synchronization
    • Preference management for repeated prompts
    • Enhanced error handling and logging
    • Modern UI with fallback to console
For more information, visit: https://github.com/LongQT-sea
"@
    
    Write-Host $helpText -ForegroundColor Cyan
}
# Parameter handling
if ($Verbose) {
    $script:Config.LogLevel = "Debug"
}
# Main execution
try {
    if ($args -contains "-help" -or $args -contains "--help" -or $args -contains "/?") {
        Show-Help
        return
    }
    
    Main
}
catch {
    Write-Log "Unexpected error: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Debug
    Show-Message "An unexpected error occurred. Check the console for details." "Error" "Error"
}
finally {
    Write-Log "Script execution finished. Exiting..." -Level Info
    Start-Sleep -Seconds 2
}
