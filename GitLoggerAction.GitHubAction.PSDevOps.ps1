#requires -Module PSDevOps
#requires -Module GitLoggerAction
Import-BuildStep -ModuleName GitLoggerAction
Push-Location $PSScriptRoot
New-GitHubAction -Name "LogGit" -Description @'
Logs to GitLogger
'@ -Action GitLoggerAction -Icon git-commit -OutputPath .\action.yml
Pop-Location