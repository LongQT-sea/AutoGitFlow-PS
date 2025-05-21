# This script automates common Git operations and workflow tasks
# Author: github.com/LongQT-sea
#
# Function to check if Git is installed and install if needed
function Main {
    # 1. Ensure Git is installed and ready for use in this session.
    $gitIsReady = Check-Git
    
    if (-not $gitIsReady) {
        return # Exit the Main function
    }
    Write-Host "`nGit command check passed."
    
    # 2. Ensure we are in a Git repository (Initialize or Clone if necessary)
    if (-not (Initialize-Or-Clone-GitRepository)) {
        Write-Host "`nGit initialization cancelled."
        return # Exit the Main function
    }
    Write-Host "`nRepository check passed."
    
    # 3. Perform Git actions based on status
    $hasLocalChanges = git -c status.relativePaths=false status --porcelain
    
    if ($hasLocalChanges) {
        Write-Host "`nLocal changes detected."
        $commitSuccess = Commit-Changes
        
        if ($commitSuccess) {
            if (-not (Test-InternetConnection)) {
                Write-Host "`nAn internet connection is required for remote operation." -ForegroundColor Red
                return # Exit the Main function
            }
            
            $remote = git remote get-url origin 2>$null
            if ($remote) {
                Write-Host "`nRemote 'origin' exists. Checking for unpushed commits..."
                Handle-UnpushedCommits
            } else {
                Write-Host "`nNo remote 'origin'. Asking to set up remote..."
                Setup-Remote
            }
        }
    } else {
        Write-Host "`nNo local changes detected."
        Show-GitStatus 
        
        if (-not (Test-InternetConnection)) {
            Write-Host "`nAn internet connection is required for remote operation." -ForegroundColor Red
            return # Exit the Main function
        }
        
        $remote = git remote get-url origin 2>$null
        if ($remote) {
            Write-Host "`nRemote 'origin' exists."
            $remoteChange = Test-RemoteChanges
            if ($remoteChange -eq "Behind" -or $remoteChange -eq "Diverged") {
                Write-Host "`nRemote changes detected: $remoteChange"
                Pull-RemoteChanges
            } else {
                Write-Host "`nNo incoming remote changes detected."
                Handle-UnpushedCommits
            }
        } else {
            Write-Host "`nNo remote 'origin' configured."
            Setup-Remote
        }
    }
}
#
# Function to check internet connectivity
function Test-InternetConnection {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        # Use a short timeout (e.g., 2000 ms)
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
    } catch {
        Write-Host "`nInternet connectivity test failed."
        return $false # Indicate failure
    }
    
    try {
        [System.Net.Dns]::GetHostEntry("github.com") | Out-Null
    } catch {
        Show-Message "Failed to resolve DNS for github.com. Cannot continue." "Connection Error" "Warning"
        return $false # Indicate failure
    }
    return $true # Indicate success
}
#
# Function to check if Git is installed and install if needed
function Check-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        return $true # Git is found and in PATH, ready.
    }
    
    # Git not found, proceed with installation attempt.
    if (-not (Confirm-Action 'Git is not installed or not in PATH. Would you like to install it now?' 'Git Installation')) {
        Write-Host "`nGit installation was cancelled by the user."
        return $false
    }
    
    if (-not (Test-InternetConnection)) {
        Show-Message "An internet connection is required to install Git." "Git Error" "Error"
        return $false
    }
    
    # Ensure Winget is available
    while (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Start-Process "ms-windows-store://pdp?hl=en-us&gl=us&productid=9nblggh4nns1"
        Start-Sleep 3 # Give Store time to open
        Show-Message "The 'winget' command is unavailable.`nPlease update `App Installer` via Microsoft Store.`n`nClick OK to continue after 'App Installer' is updated"
    }
    
    Write-Host "`nUpdating Winget sources..."
    # Suppress output of winget source update from being captured as the function's return value.
    winget source update --disable-interactivity | Out-Null 
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`nFailed to update Winget sources!"
        return $false
    }
    
    Write-Host "`nInstalling Git using Winget..."
    # Suppress any success stream output from winget install.
    # Winget's progress bar writes to the host, not the success stream, so this primarily
    # catches any final summary lines that might otherwise become the function's return value.
    $null = winget install --id=Git.Git --accept-package-agreements --accept-source-agreements --disable-interactivity --scope user
    
    # Verify installation by checking common paths
    if ((Test-Path "${env:ProgramFiles}\Git\cmd\git.exe") -or (Test-Path "${env:LOCALAPPDATA}\Programs\Git\bin\git.exe")) {
        Write-Host "`nGit was installed successfully!"
        # Git might not be available in the current session's PATH
        # Return $false to signal to Main that the current session is not ready and script execution should halt for this run.
        return $false 
    } else {
        Show-Message "Git installation failed. Please install Git manually." "Git Error" "Error"
        return $false
    }
}
#
# Function to validate email format
function Test-Email {
    param([string]$Email)
    return $Email -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
}
#
# Function to ensure Git user config is set
function Ensure-GitConfig {
    $userName = git config --global user.name
    $userEmail = git config --global user.email
    
    $configChanged = $false
    
    # Loop for user name
    while (-not $userName) {
        $userName = Get-UserInput "Enter your Git user name for commits (required):"
        if ($userName -eq $null) { # Check for Cancel button
             Show-Message "Git user name setup cancelled. Cannot proceed with operations requiring commits." "Git Config Error" "Warning"
             return $false
        }
         if ([string]::IsNullOrWhiteSpace($userName)) {
             Show-Message "User name cannot be empty." "Input Error" "Warning" 
             $userName = $null # Force loop to repeat
         }
    }
    
    # Only set if changed or initially empty
    if ($userName -ne (git config --global user.name)) {
        git config --global user.name $userName
        if ($LASTEXITCODE -ne 0) { Show-Message "Failed to set Git user name." "Git Config Error" "Error"; return $false }
        $configChanged = $true
    }
    
    # Loop for user email
    while (-not (Test-Email $userEmail)) {
         if ($userEmail -ne $null) { # Don't show error on first entry if email was initially empty
             Show-Message "Invalid email format. Please enter a valid email address." "Input Error" "Warning"
         }
        $userEmail = Get-UserInput "Enter your Git user email for commits (required):"
        if ($userEmail -eq $null) { # Check for Cancel button
             Show-Message "Git user email setup cancelled. Cannot proceed with operations requiring commits." "Git Config Error" "Warning"
             return $false
        }
         if ([string]::IsNullOrWhiteSpace($userEmail)) {
             Show-Message "User email cannot be empty." "Input Error" "Warning"
             $userEmail = $null # Ensure loop repeats if empty string entered
         }
    }
    
     # Only set if changed or initially empty
    if ($userEmail -ne (git config --global user.email)) {
        git config --global user.email $userEmail
        if ($LASTEXITCODE -ne 0) { Show-Message "Failed to set Git user email." "Git Config Error" "Error"; return $false }
        $configChanged = $true
    }
    
    if ($configChanged) {
        # Re-fetch values to display exactly what was set
        $finalUserName = git config --global user.name
        $finalUserEmail = git config --global user.email
        Show-Message "Git user configuration has been set globally:`nUser: $finalUserName`nEmail: $finalUserEmail" "Git Config"
    }
    return $true
}
#
# Function to check if we're in a Git repository
function Test-GitRepository {
    git rev-parse --is-inside-work-tree 2>$null
    # Check the exit code explicitly for reliability
    return $LASTEXITCODE -eq 0 
}
#
# Function to initialize a new Git repository OR clone an existing one
function Initialize-Or-Clone-GitRepository {
    if (Test-GitRepository) {
        # Already a git repo, nothing to do here.
        return $true
    }
    
    # Not a Git repo, ask the user what to do.
    $action = Select-InitOrCloneAction
    
    switch ($action) {
        "Init" {
            # Check directory size
            Write-Host "`nChecking directory size..."
            $currentDirSize = (Get-ChildItem . -Recurse -Force |
                Where-Object { -not $_.PSIsContainer } |
                Measure-Object -Property Length -Sum).Sum
            $thresholdBytes = 3GB
            if ($currentDirSize -gt $thresholdBytes) {
                $sizeGB = [math]::Round($currentDirSize/1GB, 1)
                $warningMessage = "The current directory size is approximately ${sizeGB} GB. Repositories larger than 3 GB are not recommended.
                `nInitializing Git in a large directory may cause performance issues and create a bloated history.
                `nConsider using a .gitignore file to exclude large files or folders before proceeding.
                `nDo you still want to initialize a Git repository here?"
                
                if (-not (Confirm-Action -Message $warningMessage -Title "Large Directory Warning")) {
                    Write-Host "`nGit initialization cancelled due to large directory size."
                    return $false # User chose not to proceed
                }
                Write-Host "`nUser confirmed to proceed despite large directory size. 'git add .' may take longer than expected." -ForegroundColor Red
            }
            
            Write-Host "`nInitializing a new Git repository in this directory..."
            # Initialize new repo with branch name 'main'
            git init -b main
            if ($LASTEXITCODE -eq 0 -and (Test-Path ".git" -PathType Container)) {
                Write-Host "`nSuccessfully initialized an empty Git repository with default branch 'main'."
                @("", "*.lnk", ".env", ".env.production", ".DS_Store", "desktop.ini") | Out-File .gitignore -Encoding utf8 -Append
                
                # Try to add .gitignore file
                $gitAddOutput = git add .gitignore 2>&1
                
                if ($LASTEXITCODE -ne 0) {
                    if ($gitAddOutput -match "detected dubious ownership") {
                        Write-Host "`nDetected Git ownership issue. Attempting to fix..." -ForegroundColor Yellow
                        # Extract the path from error message or use current directory
                        $currentPath = Get-Location
                        git config --global --add safe.directory $currentPath
                        Write-Host "`nAdded '$currentPath' to global Git safe.directory config to resolve ownership issue." -ForegroundColor Cyan
                        Write-Host "Info: You can review safe directories with 'git config --global --get-all safe.directory'." -ForegroundColor Cyan
                        
                        # Try add again after fixing
                        git add .gitignore
                        if ($LASTEXITCODE -ne 0) {
                            Write-Host "`nStill failed to stage '.gitignore', check console for detail"
                            return $false
                        }
                    } else {
                        Write-Host "`nFailed to stage '.gitignore', check console for detail"
                        return $false
                    }
                }
                
                git commit -m "Add gitignore"
                Write-Host "`n.gitignore added"
                # Disable Git line ending safety warnings (LF vs CRLF) for this repo
                git config core.safecrlf false
                Write-Host "`nDisabled Git line ending safety warnings (LF vs CRLF) for this repo"
                return $true
            } else {
                Write-Host "`nFailed to initialize Git repository."
                return $false
            }
        }
        "Clone" {
            # Check internet
            if (-not (Test-InternetConnection)) {
                Write-Host "`nAn internet connection is required to clone." -ForegroundColor Red
                return $false
            }
            
            $remoteUrl = Get-UserInput "Enter the remote repository URL to clone:"
            
            if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
                Show-Message "Clone operation cancelled: No URL provided." "Git Clone" "Warning"
                return $false
            }
            
            # Validate basic URL format
            if ($remoteUrl -notmatch '^(https?|git@)') {
                Show-Message "The URL provided does not appear valid. Must start with http, https, or git@." "Invalid URL" "Warning"
                return $false
            }
            
            # Ask for shallow clone
            $useShallow = Confirm-Action -Message "Do you want to use shallow clone (--depth=1)?" -Title "Shallow Clone"
            
            Write-Host "`nAttempting to clone $remoteUrl..."
            Write-Host "(This will create a new sub-directory named after the repository).`n"
            
            $cloneArgs = if ($useShallow) { "--depth=1" } else { "" }
            git clone $cloneArgs $remoteUrl
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "`nClone command finished successfully!"
                
                # Extract folder name from URL
                $repoName = [System.IO.Path]::GetFileNameWithoutExtension($remoteUrl)
                if (Test-Path $repoName) {
                    Set-Location $repoName
                    Write-Host "`nChanged directory to .\$repoName"
                }
                
                return $true
            } else {
                Write-Host "`nClone command failed! Exit code: $LASTEXITCODE"
                return $false
            }
        }
        default {
            # User cancelled the Init/Clone selection dialog
            return $false
        }
    }
}
#
# Function to display repository status
function Show-GitStatus {
    if (-not (Test-GitRepository)) { 
        Show-Message "Not inside a Git repository." "Git Status Error" "Warning"
        return 
    }
    
    $branch = $(git branch --show-current)
    $remote = git remote get-url origin 2>$null
    
    $statusMessage = "Current Branch: $($branch)`n`n"
    
    if ($remote) {
        $statusMessage += "Remote 'origin': $remote`n`n"
    } else {
        $statusMessage += "No remote 'origin' configured`n`n"
    }
    
    if ($remote) {
        $statusAgainstRemote = $(git status -uno)
        if ($statusAgainstRemote -match "branch is up to date") {
            $statusMessage += "Your branch is up to date with 'origin/$branch'.`n`n"
        } elseif ($statusAgainstRemote -match "branch is ahead") {
            $statusMessage += "Your branch is ahead of 'origin/$branch'.`n`n"
        } elseif ($statusAgainstRemote -match "branch is behind") {
            $statusMessage += "Your branch is behind of 'origin/$branch'.`n`n"
        } elseif ($statusAgainstRemote -match "have diverged") {
            $statusMessage += "Branch has diverged from 'origin/$branch'.`n`n"
        } else {
            Write-Host "`nCould not determine status relative to remote."
        }
    }
    
    $gitStatusOutput = git status --porcelain
    if ([string]::IsNullOrWhiteSpace($gitStatusOutput)) {
        $statusMessage += "Status: Working tree clean"
    } else {
        $statusMessage += "Status:`n$gitStatusOutput"
        $statusMessage += "`n`nRun 'git status' in terminal for more details."
    }
    
    $lastCommits = git log -3 --pretty=format:"%h - %s (%cr)" | Out-String
    $statusMessage += "`n`nLast 3 commits:`n$lastCommits"
    
    Show-Message $statusMessage "Git Status"
    
    # Ideally, this should run before $statusAgainstRemote, but doing so would delay Show-Message $statusMessage, so it runs last instead.
    if ($remote) {
        Write-Host "`nChecking remote status..."
        git remote update origin --prune | Out-Null
    }
}
#
# Function to set up remote 'origin'
function Setup-Remote {
    # This function is called ONLY if a local repo exists but has no 'origin' remote.
    # Assumption: User wants to link this local repo to a NEW or EMPTY remote repo.
    
    # Ensure Git user configuration is set before potentially committing/pushing
    if (-not (Ensure-GitConfig)) {
        return
    }
    
    # Check if "Don't ask again" marker exists
    $markerPath = Join-Path (git rev-parse --git-dir 2>$null) "Skip_git_remote.marker"
    if (-not [string]::IsNullOrEmpty($markerPath) -and (Test-Path $markerPath)) {
        Write-Host "`nSkipping remote setup based on marker file: $markerPath" -ForegroundColor Cyan
        return
    }
    
    $setupOptions = [System.Windows.MessageBoxButton]::YesNoCancel
    $setupQuestion = "No 'origin' remote configured. Would you like to add one now?`n`n(This typically links your local repository to an NEW or EMPTY remote repository like one on GitHub/GitLab, allowing you to push your code.)`n`nYes - Add remote now`nNo - Skip for now`nCancel - Don't ask again for this repository"
    $setupResult = [System.Windows.MessageBox]::Show($setupQuestion, "Git Remote Setup", $setupOptions, "Question")
    
    switch ($setupResult) {
        "Yes" {
            
            $remoteUrl = Get-UserInput "Enter the remote repository URL (e.g., HTTPS or SSH):"
            
            if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
                Show-Message "Remote setup cancelled: No URL provided." "Git Remote" "Warning"
                return
            }
            
            # Add the remote
            Write-Host "`nAdding remote 'origin' with URL: $remoteUrl"
            git remote add origin $remoteUrl
            if ($LASTEXITCODE -ne 0) {
                Show-Message "Failed to add remote 'origin'. Check the URL and ensure it's not already in use with a different name." "Git Error" "Error"
                return
            }
            Write-Host "`nRemote 'origin' added successfully."
            
            # Check if remote has any branches
            $remoteBranches = git ls-remote --heads origin
            if (-not $remoteBranches) {
                Write-Host "`nRemote has no branches. Skipping pull."
            } else {
                # Pull from remote
                git pull origin (git branch --show-current)
                if ($LASTEXITCODE -ne 0) {
                    Show-Message "Failed to pull from remote 'origin/$branch'." "Git Error" "Error"
                    return
                }
            }
        }
        "No" {
            # Skip for this run
            return
        }
        "Cancel" {
            # Don't ask again marker
            try {
                New-Item -Path $markerPath -ItemType File -Force | Out-Null
                Write-Host "`nSaved '$markerPath' as a flag to skip future prompts." -ForegroundColor Cyan
            } catch { Show-Message "Could not create the marker file to skip future prompts: $($_.Exception.Message)" "File Error" "Warning"}
            return
        }
        Default {
            return
        }
    }
}
#
# Function to check for remote changes
function Test-RemoteChanges {
    Write-Host "`nFetching from remote..."
    git fetch origin 2>$null
    if ($LASTEXITCODE -ne 0) {
        Show-Message "Failed to fetch from remote 'origin'. Try running 'git fetch origin' manually." "Git Fetch Error" "Warning"
        return $false
    }
    
    $tracking = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if (-not $tracking) { return $false }
    
    $local     = git rev-parse "@"  
    $remoteRef = git rev-parse "@{u}"
    $base      = git merge-base "@" "@{u}"
    
    if ($local -eq $remoteRef) {
        return $false # Up to date
    } elseif ($local -eq $base) {
        return "Behind"  # Need to pull
    } elseif ($remoteRef -eq $base) {
        return "Ahead"   # Need to push
    } else {
        return "Diverged" # Both have new commits
    }
}
#
# Function to pull changes from remote
function Pull-RemoteChanges {
    # Check if "Don't ask again" marker exists
    $markerPath = Join-Path (git rev-parse --git-dir 2>$null) "Skip_pull_changes.marker"
    if (-not [string]::IsNullOrEmpty($markerPath) -and (Test-Path $markerPath)) {
        Write-Host "`nSkipping pull changes based on marker file: $markerPath" -ForegroundColor Cyan
        return
    }
    
    $branch = $(git branch --show-current)
    $msg = "There may be new changes on remote 'origin/$branch'.`n`nYes - Pull now`nNo - Skip for now`nCancel - Don't ask again for this repository"
    $result = [System.Windows.MessageBox]::Show($msg, "Pull Remote Changes", [System.Windows.MessageBoxButton]::YesNoCancel, "Question")
    
    switch ($result) {
        "Yes" {
            Write-Host "`nPulling changes from remote 'origin'..."
            git pull origin $branch
            if ($LASTEXITCODE -ne 0) {
                Show-Message "Failed to pull changes from remote repository. Check for conflicts or errors in the terminal." "Git Pull Error" "Error"
                return
            }
            Write-Host "`nSuccessfully pulled changes."
            return
        }
        "No" {
            return
        }
        "Cancel" {
            # Don't ask again marker
            try {
                New-Item -Path $markerPath -ItemType File -Force | Out-Null
                Write-Host "`nSaved '$markerPath' as a flag to skip future prompts." -ForegroundColor Cyan
            } catch { Show-Message "Could not create the marker file to skip future prompts: $($_.Exception.Message)" "File Error" "Warning"}
            return
        }
        Default {
            return
        }
    }
}
#
# Function to push changes to remote
function Push-Changes {
    $branch = $(git branch --show-current)
    Write-Host "`nPushing changes to remote 'origin' branch '$branch'..."
    
    # Use -u to set upstream tracking if it's not set already
    git push -u origin $branch 
    
    if ($LASTEXITCODE -ne 0) {
        Show-Message "Failed to push changes to remote repository. Check terminal for details (e.g., authentication, conflicts)." "Git Push Error" "Error"
        return
    } else {
        Write-Host "`nSuccessfully pushed changes to remote repository."
        return
    }
}
#
# Function to handle unpushed commits notification
function Handle-UnpushedCommits {
    # Check if "Don't ask again" marker exists
    $markerPath = Join-Path (git rev-parse --git-dir 2>$null) "Skip_unpushed_commits.marker"
    if (-not [string]::IsNullOrEmpty($markerPath) -and (Test-Path $markerPath)) {
        Write-Host "`nSkipping unpushed commits based on marker file: $markerPath" -ForegroundColor Cyan
        return
    }
    
    # Check if the current branch has a remote tracking branch configured
    $upstream = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if (-not $upstream) {
        # No upstream branch set, might be first push needed.
        # Let's check if there are *any* commits ahead of *any* remote branch (less precise but useful)
        $unpushedLog = git log --branches --not --remotes --oneline 2>$null
    } else {
        # Upstream is set, check specifically against it
        $unpushedLog = git log '@{u}..HEAD' --oneline 2>$null
    }
    
    if ($unpushedLog) {
        $commitLines = ($unpushedLog -split "`n") | Where-Object { $_ } # Split and remove empty lines
        $commitCount = $commitLines.Count
        $commitDisplay = ($commitLines | Select-Object -First 5) -join "`n" # Show first 5
        if ($commitCount -gt 5) { $commitDisplay += "`n...and $($commitCount - 5) more."}
    
        $setupOptions = [System.Windows.MessageBoxButton]::YesNoCancel
        $commitMsg = "You have $commitCount unpushed commit(s):`n$commitDisplay`n`nDo you want to push them to remote origin now?`n`nYes - Push now`nNo - Skip for now`nCancel - Don't ask again for this repository"
        $commitResult = [System.Windows.MessageBox]::Show($commitMsg, "Unpushed Commits", $setupOptions, "Question")
        
        switch ($commitResult) {
            "Yes" {
                return Push-Changes # Attempt push
            }
            "No" {
                return # Skip for now
            }
            "Cancel" {
                # Don't ask again marker
                try {
                    New-Item -Path $markerPath -ItemType File -Force | Out-Null
                    Write-Host "`nSaved '$markerPath' as a flag to skip future prompts." -ForegroundColor Cyan
                } catch { Show-Message "Could not create the marker file to skip future prompts: $($_.Exception.Message)" "File Error" "Warning"}
                return
            }
            Default {
                return
            }
        }
    }
    
    return # No unpushed commits found
}
#
# Function to commit changes
function Commit-Changes {
    # Ensure Git user configuration is set before committing
    if (-not (Ensure-GitConfig)) {
        return $false # Config setup failed or cancelled
    }
    # Get the more verbose status for the user message
    $gitStatusOutput = git -c status.relativePaths=false status | Out-String
    # Split into lines for display truncation
    $lines = $gitStatusOutput -split "`r?`n"
    $maxLinesToShow = 20
    if ($lines.Count -gt $maxLinesToShow) {
        $displayStatus = ($lines | Select-Object -First $maxLinesToShow) -join "`n"
        $displayStatus += "`n`n...(Status truncated, run 'git status' for full details)..."
    } else {
        $displayStatus = $gitStatusOutput
    }
    # --- Confirmation Prompt with YesNoCancel ---
    $promptTitle = "Stage & Commit Changes"
    $promptMessage = @"
The following changes were detected:
$displayStatus
What would you like to do?
 - YES:    Stage ALL changes (`git add .`) AND then Commit them.
 - NO:     Stage ALL changes (`git add .`).
 - CANCEL: Do nothing (skip staging and committing).
"@
    $buttons = [System.Windows.MessageBoxButton]::YesNoCancel
    $icon = [System.Windows.MessageBoxImage]::Question
    $result = [System.Windows.MessageBox]::Show($promptMessage, $promptTitle, $buttons, $icon)
    switch ($result) {
        "Yes" {
            # --- User clicked YES: Stage AND Commit ---
            Write-Host "`nStaging all detected changes..."
            git add .
            # Check if staging failed
            if ($LASTEXITCODE -ne 0) {
                 Show-Message "Error: Failed to stage changes using 'git add .'." "Git Add Error" "Error"
                 return $false # Stop if staging fails
            }
            Write-Host "`nStaging successful."
            
            # Check if anything was effectively staged (important after add .)
            if (git diff --staged --quiet) {
                # --quiet exits with 0 if no changes, 1 if changes
                Show-Message "Staging ran, but no effective changes were staged (perhaps only ignored files or conflicts resolved without changes). Cannot proceed with commit." "Git Commit" "Warning"
                return $false # Nothing to commit even after staging
            }
            
            # Get commit message
            $defaultCommitMsg = "Update $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            $commitMsg = Get-UserInput -Prompt "Enter commit message:" -DefaultValue $defaultCommitMsg -Title "Git Commit Message"
            if ($commitMsg -eq $null) { # User pressed Cancel on commit message input
                Show-Message "Commit cancelled by user. Changes remain staged." "Git Commit"
                # Return $false because the *commit* was cancelled, even though staging happened.
                # The main script logic expects 'true' only on successful commit.
                return $false
            }
            
            if ([string]::IsNullOrWhiteSpace($commitMsg)) {
                 Write-Host "`nEmpty commit message entered, using default: '$defaultCommitMsg'"
                 $commitMsg = $defaultCommitMsg
            }
            
            # Commit changes
            Write-Host "`nCommitting staged changes with message: $commitMsg"
            $commitOutput = git commit -m $commitMsg 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                # Handle potential errors during commit
                Show-Message "Failed to commit changes. Error:`n$commitOutput" "Git Commit Error" "Error"
                return $false # Commit failed, staging happened
            } else {
                Write-Host "`nChanges staged and committed successfully."
                return $true # Commit was successful
            }
        } # End Yes
        
        "No" {
            # --- User clicked NO: Only Stage ---
            Write-Host "`nStaging all detected changes..."
            git add .
            if ($LASTEXITCODE -ne 0) {
                Show-Message "Error: Failed to stage changes using 'git add .'." "Git Add Error" "Error"
                # Even though user said No to commit, staging failure is an error
                return $false
            }
            
            # Check if anything was effectively staged
            if (git diff --staged --quiet) {
                Write-Host "`nStaging ran, but no effective changes were staged. Nothing added."
            } else {
                Write-Host "`nChanges were staged successfully. You can commit them later."
            }
            
            # Return false because a commit did NOT happen, which is important for the calling script's logic
            return $false
        } # End No
        
        "Cancel" {
            # --- User clicked CANCEL: Do Nothing ---
            Write-Host "`nOperation cancelled. No changes were staged or committed."
            return $false # No action taken
        } # End Cancel
        
        Default {
            # Should not happen with YesNoCancel
            return $false
        }
    } # End Switch
}
#
#
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
#
# Function to display messages in a dialog box
function Show-Message {
    param(
        [string]$Message,
        [string]$Title = "AutoGitFlow",
        [string]$Icon = "None"
    )
    
    # Map simple names to MessageBoxImage enum values
    $iconEnum = switch ($Icon.ToLower()) {
        'error'       { [System.Windows.MessageBoxImage]::Error }
        'warning'     { [System.Windows.MessageBoxImage]::Warning }
        'information' { [System.Windows.MessageBoxImage]::Information }
        default       { [System.Windows.MessageBoxImage]::None }
    }
    
    [void][System.Windows.MessageBox]::Show($Message, $Title, [System.Windows.MessageBoxButton]::OK, $iconEnum)
}
#
# Function to confirm actions with the user
function Confirm-Action {
    param(
        [string]$Message,
        [string]$Title = "AutoGitFlow"
    )
    
    $result = [System.Windows.MessageBox]::Show($Message, $Title, "YesNo", "Question")
    return $result -eq "Yes"
}
#
# Function to get user input
function Get-UserInput {
    param(
        [string]$Prompt,
        [string]$DefaultValue = "",
        [string]$Title = "AutoGitFlow"
    )
    
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    
    [xml]$xaml = @"
    <Window 
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title" 
        SizeToContent="Height" 
        Width="450"
        MinHeight="180"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#F5F5F5">
        <Grid Margin="15">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            
            <TextBlock Grid.Row="0" Text="$Prompt" Margin="0,0,0,10" FontSize="13" TextWrapping="Wrap"/>
            
            <TextBox x:Name="InputTextBox" Grid.Row="1" MinHeight="30" Padding="5" FontSize="13" VerticalContentAlignment="Center" Text="$DefaultValue" AcceptsReturn="False"/>
            
            <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,15,0,0">
                <Button x:Name="CancelButton" Content="Cancel" Width="80" Height="30" Margin="0,0,10,0" Background="#E1E1E1" IsCancel="True"/>
                <Button x:Name="OKButton" Content="OK" Width="80" Height="30" Background="#007ACC" Foreground="White" IsDefault="True"/>
            </StackPanel>
        </Grid>
    </Window>
"@
    
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    try {
        $window = [System.Windows.Markup.XamlReader]::Load($reader)
    } catch {
        Write-Error "Error loading XAML: $($_.Exception.Message)"
        # Fallback to basic input if XAML fails
        Write-Host "`n$Prompt ($DefaultValue): " -NoNewline
        $input = Read-Host
        return if ([string]::IsNullOrWhiteSpace($input)) { $DefaultValue } else { $input }
    }
    
    $inputTextBox = $window.FindName("InputTextBox")
    $okButton = $window.FindName("OKButton")
    $cancelButton = $window.FindName("CancelButton")
    
    $script:userInputResult = $null
    $script:userDialogResult = $false
    
    $okButton.Add_Click({
        $script:userInputResult = $inputTextBox.Text # Return even if empty, let caller decide
        $script:userDialogResult = $true
        $window.Close()
    })
    
    $cancelButton.Add_Click({
        $script:userInputResult = $null
        $script:userDialogResult = $false
        $window.Close()
    })
    
    $inputTextBox.Add_Loaded({
        $inputTextBox.Focus()
        $inputTextBox.SelectAll()
    })
    
    # Handle Enter key press in TextBox
    $inputTextBox.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq 'Return') {
            # Simulate OK button click
            $okButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        }
    })
    
    $null = $window.ShowDialog()
    
    if ($script:userDialogResult) {
        return $script:userInputResult
    } else {
        return $null # Explicitly return null on Cancel
    }
}
#
# Function to ask user whether to Init or Clone (Improved UI)
function Select-InitOrCloneAction {
    param(
        [string]$Title = "Git Initialization"
    )
    
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    
    [xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="$Title"
    SizeToContent="WidthAndHeight"
    MinWidth="420" 
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize"
    Background="#F5F5F5"
    UseLayoutRounding="True">
    <Border Padding="20"> <!-- Added padding around the main content -->
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/> <!-- Allow text block to wrap and take space -->
                <RowDefinition Height="Auto"/> <!-- Button panel height -->
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Text="This directory is not a Git repository. What would you like to do?" Margin="0,0,0,25" FontSize="14" TextWrapping="Wrap"/>
            <!-- Buttons aligned to the right -->
            <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="InitButton" 
                        Content="Initialize New Repo Here" 
                        MinWidth="130" Height="30" Padding="10,0" Margin="0,0,10,0" 
                        Background="#007ACC" Foreground="White"/>
                <Button x:Name="CloneButton" 
                        Content="Clone a Remote Repo" 
                        MinWidth="130" Height="30" Padding="10,0" Margin="0,0,10,0" 
                        Background="#5cb85c" Foreground="White"/>
                <Button x:Name="CancelButton" 
                        Content="Cancel" 
                        MinWidth="80" Height="30" Padding="10,0" 
                        Background="#E1E1E1" IsCancel="True"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@
    
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    try {
        $window = [System.Windows.Markup.XamlReader]::Load($reader)
    } catch {
        Write-Error "Error loading XAML for Init/Clone selection: $($_.Exception.Message)"
        # Fallback or error handling
        return $null
    }
    
    $initButton = $window.FindName("InitButton")
    $cloneButton = $window.FindName("CloneButton")
    $cancelButton = $window.FindName("CancelButton")
    
    $script:initCloneChoice = $null # Store the choice: "Init", "Clone", or null for Cancel
    
    $initButton.Add_Click({
        $script:initCloneChoice = "Init"
        $window.Close()
    })
    
    $cloneButton.Add_Click({
        $script:initCloneChoice = "Clone"
        $window.Close()
    })
    
    $cancelButton.Add_Click({
        $script:initCloneChoice = $null
        $window.Close()
    })
    
    # Make window topmost to ensure visibility
    # $window.Topmost = $true # Usually not needed unless other windows might overlap aggressively
    $null = $window.ShowDialog()
    # $window.Topmost = $false
    
    return $script:initCloneChoice
}
#
# --- Main Script Execution ---
#
Write-Host "`nStarting AutoGitFlow Script..." -ForegroundColor Green
#
Main
#
Write-Host "`nAutoGitFlow Script finished. Exiting..." -ForegroundColor Green
Start-Sleep 3
