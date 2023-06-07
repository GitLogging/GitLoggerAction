@{
    ModuleVersion = '0.1.2'
    Description   = 'GitHub Action for GitLogger'
    PrivateData   = @{
        PSData = @{
            ReleaseNotes = @'
# GitHub Action 0.1.2:
* Supporting CommitBranch/IsPrivateRepository (#6)
* Not logging within a pull request (#7)
* Automatically tagging releases (#8)
'@
        }
    }
}
