if ($env:GITHUB_WORKSPACE) {
    git fetch
}

$progId = Get-Random


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

$gitRemoteUrl = git remote | git remote get-url | Select-Object -First 1
Write-Progress "Getting Logs" " $gitRemotUrl " -Id $progId

$allLogs = git log --stat | 
    Foreach-Object {
        $_.CommitDate = $_.CommitDate.ToString('s')
        $_.GitOutputLines = $_.GitOutputLines -join [Environment]::NewLine
        $_ |
            Add-Member NoteProperty RepositoryURL $gitRemoteUrl.RemoteUrl -Force -PassThru
    }

$allJson = $allLogs | ConvertTo-Json -Depth 20

$headBranch = git remote |
    Select-Object -First 1 |
    git remote show |
    Select-Object -ExpandProperty HeadBranch
$currentBranch = git branch | Where-Object IsCurrentBranch

if ($currentBranch -eq $headBranch) {
    # If the current branch is head branch, get the last N commits

} else {
    # Get all commits on the current branch
}

$gitLoggerPushUrl = 'https://gitloggerfunction.azurewebsites.net/PushGitLogger/'

$gotResponse = Invoke-RestMethod -Uri $gitLoggerPushUrl

if (-not $gotResponse) {
    Write-Error "$gitloggerPushUrl unavailable"
    return
}

$repoRestUrl = $gitLoggerPushUrl + '/' + ($gitRemoteUrl.RemoteUrl -replace '^(?>https?|git|ssh)://' -replace '\.git$') + '.git'
$Result = Invoke-RestMethod -Uri $repoRestUrl -Body $allJson -Method Post

"Logged $($result) commits to GitLogger" | Out-Host


