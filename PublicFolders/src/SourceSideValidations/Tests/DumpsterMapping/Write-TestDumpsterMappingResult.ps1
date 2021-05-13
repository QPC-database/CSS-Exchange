﻿function Write-TestDumpsterMappingResult {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [object]
        $TestResult
    )

    begin {
        $badDumpsters = [System.Collections.ArrayList]::new()
    }

    process {
        $badDumpsters += $TestResult
    }

    end {
        if ($badDumpsters.Count -gt 0) {
            Write-Host
            Write-Host $badDumpsters.Count "folders have invalid dumpster mappings."
            Write-Host $badDumpsters[0].ActionRequired
        }
    }
}
