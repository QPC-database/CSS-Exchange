﻿[CmdletBinding()]
param(
    [Switch]
    $Save
)

#Requires -Version 7

. $PSScriptRoot\Load-Module.ps1

if (-not (Load-Module -Name PSScriptAnalyzer)) {
    throw "PSScriptAnalyzer module could not be loaded"
}

if (-not (Load-Module -Name EncodingAnalyzer)) {
    throw "EncodingAnalyzer module could not be loaded"
}

$repoRoot = Get-Item "$PSScriptRoot\.."

$scriptFiles = Get-ChildItem -Path $repoRoot -Directory | Where-Object {
    $_.Name -ne "dist" } | ForEach-Object { Get-ChildItem -Path $_.FullName -Include "*.ps1", "*.psm1" -Recurse } | ForEach-Object { $_.FullName }
$filesFailed = $false

# MD files must NOT have a BOM
Get-ChildItem -Path $repoRoot -Include *.md -Recurse | ForEach-Object {
    $encoding = Get-Encoding $_
    if ($encoding.BOM) {
        Write-Warning "MD file has BOM: $($_.FullName)"
        if ($Save) {
            try {
                $content = Get-Content $_
                Set-Content -Path $_.FullName -Value $content -Encoding utf8NoBOM -Force
                Write-Warning "Saved $($_.FullName) without BOM."
            } catch {
                $filesFailed = $true
                throw
            }
        } else {
            $filesFailed = $true
        }
    }
}

foreach ($file in $scriptFiles) {
    # PS1 files must have a BOM
    $encoding = Get-Encoding $file
    if (-not $encoding.BOM) {
        Write-Warning "File has no BOM: $file"
        if ($Save) {
            try {
                $content = Get-Content $file
                Set-Content -Path $file -Value $content -Encoding utf8BOM -Force
                Write-Warning "Saved $file with BOM."
            } catch {
                $filesFailed = $true
                throw
            }
        } else {
            $filesFailed = $true
        }
    }

    $before = Get-Content $file -Raw
    $after = Invoke-Formatter -ScriptDefinition (Get-Content $file -Raw) -Settings $repoRoot\PSScriptAnalyzerSettings.psd1

    if ($before -ne $after) {
        Write-Warning ("{0}:" -f $file)
        Write-Warning ("Failed to follow the same format defined in the repro")
        if ($Save) {
            try {
                Set-Content -Path $file -Value $after -Encoding utf8NoBOM
                Write-Information "Saved $file with formatting corrections."
            } catch {
                $filesFailed = $true
                Write-Warning "Failed to save $file with formatting corrections."
            }
        } else {
            $filesFailed = $true
            git diff ($($before) | git hash-object -w --stdin) ($($after) | git hash-object -w --stdin)
        }
    }

    $analyzerResults = Invoke-ScriptAnalyzer -Path $file -Settings $repoRoot\PSScriptAnalyzerSettings.psd1
    if ($null -ne $analyzerResults) {
        $filesFailed = $true
        $analyzerResults | Format-Table -AutoSize
    }
}

if ($filesFailed) {
    throw "Failed to match coding formatting requirements"
}
