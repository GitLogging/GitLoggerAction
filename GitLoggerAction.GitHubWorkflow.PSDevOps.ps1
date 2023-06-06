#requires -Module PSDevOps
Push-Location $PSScriptRoot
Import-BuildStep -ModuleName GitLoggerAction
New-GitHubWorkflow -Name "Test GitLogger Action" -On Push,     
    Demand -Job BuildGitLoggerAction -OutputPath .\.github\workflows\BuildGitLoggerAction.yml 

Pop-Location