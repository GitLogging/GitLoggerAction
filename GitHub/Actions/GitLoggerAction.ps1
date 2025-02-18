$ErrorActionPreference = 'continue'
if ($env:GITHUB_WORKSPACE) {
    git fetch --unshallow
}

$progId = Get-Random


$gitHubEvent = if ($env:GITHUB_EVENT_PATH) {
    [IO.File]::ReadAllText($env:GITHUB_EVENT_PATH) | ConvertFrom-Json
} else { $null }

@"
::group::GitHubEvent
$($gitHubEvent | ConvertTo-Json -Depth 100)
::endgroup::
"@ | Out-Host


$imported = foreach ($moduleRequirement in 'ugit') {
    Write-Progress "Importing Modules" "$moduleRequirement" -Id $progId
    $requireLatest = $false
    $ModuleLoader  = $null
    # If the module requirement was a string
    if ($moduleRequirement -is [string]) {
        # see if it's already loaded
        $foundModuleRequirement = Get-Module $moduleRequirement
        if (-not $foundModuleRequirement) {
            # If it wasn't,
            $foundModuleRequirement = try { # try loading it
                Import-Module -Name $moduleRequirement -PassThru -Global -ErrorAction SilentlyContinue
            } catch {
                $null
            }
        }
        # If we found a version but require the latest version,
        if ($foundModuleRequirement -and $requireLatest) {
            # then find if there is a more recent version.
            Write-Verbose "Searching for a more recent version of $($foundModuleRequirement.Name)@$($foundModuleRequirement.Version)"
            if (-not $script:FoundModuleVersions) {
                $script:FoundModuleVersions = @{}
            }
            if (-not $script:FoundModuleVersions[$foundModuleRequirement.Name]) {
                $script:FoundModuleVersions[$foundModuleRequirement.Name] = Find-Module -Name $foundModuleRequirement.Name       

            }
            $foundModuleInGallery = $script:FoundModuleVersions[$foundModuleRequirement.Name]
            if ($foundModuleInGallery -and
                ([Version]$foundModuleInGallery.Version -gt [Version]$foundModuleRequirement.Version)) {
                Write-Verbose "$($foundModuleInGallery.Name)@$($foundModuleInGallery.Version)"
                # If there was a more recent version, unload the one we already have
                $foundModuleRequirement | Remove-Module # Unload the existing module
                $foundModuleRequirement = $null
            } else {
                Write-Verbose "$($foundModuleRequirement.Name)@$($foundModuleRequirement.Version) is the latest"
            }
        }
        # If we have no found the required module at this point
        if (-not $foundModuleRequirement) {
            if ($moduleLoader) { # load it using a -ModuleLoader (if provided)
                $foundModuleRequirement = . $moduleLoader $moduleRequirement
            } else {
                # or install it from the gallery.
                Install-Module -Name $moduleRequirement -Scope CurrentUser -Force -AllowClobber
                if ($?) {
                    # Provided the installation worked, try importing it
                    $foundModuleRequirement =
                        Import-Module -Name $moduleRequirement -PassThru -Global -ErrorAction SilentlyContinue
                }
            }
        } else {
            $foundModuleRequirement
        }
    }
}

$gitRemoteUrl = git remote | git remote get-url | Select-Object -First 1 -ExpandProperty RemoteUrl
$GetGitLoggerUrl = 'https://gitloggerfunction.azurewebsites.net/GetGitLogger/'
$gotError = $false
$timeSinceLastLoggedCommit = $null
$gotResponse = try {
    Invoke-RestMethod -Uri "${GetGitLoggerUrl}?Repository=$gitRemoteUrl&SortBy=CommitDate&First=1&Property=CommitDate" -ErrorAction SilentlyContinue -ErrorVariable gotError
} catch {
    $gotError = $_
    $_
}
if ($gotResponse.CommitDate) {
    $timeSinceLastLoggedCommit = [DateTime]::Now - $gotResponse.CommitDate
}
elseif ($gotResponse -is [Management.Automation.ErrorRecord]) {
    # Nothing exists yet
}

Write-Progress "Getting Logs" " $gitRemotUrl " -Id $progId

$gitRemote = git remote
$headBranch = git remote |
    Select-Object -First 1 |
    git remote show |
    Select-Object -ExpandProperty HeadBranch
$currentBranch = git branch | Where-Object IsCurrentBranch

if ($currentBranch.BranchName -like '*detached*' -or $currentBranch.Detached) {
    "On Detached Branch, not logging." | Out-Host
    return
}

$distinctHash = @{}

filter FlattenLogObject {
    if (-not $_.CommitDate) { return }
    $logObject = $_    
    $logObject.GitOutputLines = $logObject.GitOutputLines -join [Environment]::NewLine
    if ($distinctHash[$logObject.CommitHash]) {
        return
    }
    $distinctHash[$logObject.CommitHash] = $true
    # CommitDate is a ScriptProperty, so we need to convert it to a NoteProperty in a fixed format.
    # We start by capturing the variable
    $commitDate = $logObject.CommitDate.ToString('s')
    # Then we add a property
    $logObject.psobject.properties.add(
        # with the overridden value        
        [psnoteproperty]::new('CommitDate',$commitDate),
        $true # (passing $true to force the override)
    )
    $logObject |
        Add-Member NoteProperty RepositoryURL $gitRemoteUrl -Force -PassThru |
        Add-Member NoteProperty IsPrivateRepository ($gitHubEvent.repository.private -as [bool]) -Force -PassThru |
        Add-Member NoteProperty CommitBranch $currentBranch.BranchName -Force -PassThru
}


$allLogs = 
if ($currentBranch.BranchName -eq $headBranch) {
    # If the current branch is head branch, see if we know the time of the last commit
    if (-not $timeSinceLastLoggedCommit) {
        "Logging All Changes" | Out-Host
        git log -Statistics |
            FlattenLogObject
    } else {
        "Logging Within a Week of $($gotResponse.CommitDate)" | Out-Host
        # If we already have commits, get logs since a week before the last known commit.        
        git log -Statistics -Since ($gotResponse.CommitDate.AddDays(-7)) | 
            FlattenLogObject
    }
} else {    
    "Logging Changes from $currentBranch" | Out-Host
    git log "$($gitRemote.RemoteName)/$headBranch..$CurrentBranch" -Statistics    |
        FlattenLogObject
    # Get all commits on the current branch
}

$allJson = $allLogs | ConvertTo-Json -Depth 20

$gitLoggerPushUrl = 'https://gitloggerfunction.azurewebsites.net/PushGitLogger'

$gotResponse = try {
    Invoke-RestMethod -Uri $gitLoggerPushUrl
} catch {
    $gotError = $_
    $false
}

if (-not $gotResponse) {
    Write-Error "$gitloggerPushUrl unavailable"
    return
}

$repoRestUrl = $gitLoggerPushUrl + '/' + ($gitRemoteUrl -replace '^(?>https?|git|ssh)://' -replace '\.git$') + '.git'

$Result = 
    try {
        Invoke-RestMethod -Uri $repoRestUrl -Body $allJson -Method Post
    } catch {
        "::error::$($_ | Out-String -Width 1kb)"
    }

"Logged $($result) commits to $repoRestUrl" | Out-Host

# Always exiting zero, because we don't want to fail the build if this fails
# (a failure to log should not be a failure to build)
exit 0