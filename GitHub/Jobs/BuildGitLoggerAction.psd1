@{
    "runs-on" = "ubuntu-latest"    
    if = '${{ success() }}'
    steps = @(
        @{
            name = 'Check out repository'
            uses = 'actions/checkout@v2'
        },
        @{
            name = 'Run GitLogger (from main)'
            if   = '${{github.ref_name == ''main''}}'
            uses = 'GitLogging/GitLoggerAction@main'
            id = 'GitLoggerMain'
        },
        @{
            name = 'Run GitLogger (on branch)'
            if   = '${{github.ref_name != ''main''}}'
            uses = './'
            id = 'GitLoggerBranch'
        },
        'TagModuleVersion',
        'ReleaseModule'
    )
}