﻿function Get-FolderData {
    [CmdletBinding()]
    param (
        [Parameter()]
        [bool]
        $StartFresh = $true,

        [Parameter()]
        [bool]
        $SlowTraversal = $false
    )

    begin {
        $startTime = Get-Date
        $serverName = (Get-Mailbox -PublicFolder (Get-OrganizationConfig).RootPublicFolderMailbox.HierarchyMailboxGuid.ToString()).ServerName
        $folderData = [PSCustomObject]@{
            IpmSubtree              = $null
            IpmSubtreeByMailbox     = $null
            ParentEntryIdCounts     = @{}
            EntryIdDictionary       = @{}
            NonIpmSubtree           = $null
            NonIpmEntryIdDictionary = @{}
            MailboxToServerMap      = @{}
            ItemCounts              = @()
            ItemCountDictionary     = @{}
        }
    }

    process {
        if (-not $StartFresh -and (Test-Path $PSScriptRoot\IpmSubtree.csv)) {
            $folderData.IpmSubtree = Import-Csv $PSScriptRoot\IpmSubtree.csv
            $folderData.NonIpmSubtree = Import-Csv $PSScriptRoot\NonIpmSubtree.csv
            $folderData.ItemCounts = Import-Csv $PSScriptRoot\ItemCounts.csv
        } else {
            Add-JobQueueJob @{
                ArgumentList = $serverName, $SlowTraversal
                Name         = "Get-IpmSubtree"
                ScriptBlock  = ${Function:Get-IpmSubtree}
            }

            Add-JobQueueJob @{
                ArgumentList = $serverName, $SlowTraversal
                Name         = "Get-NonIpmSubtree"
                ScriptBlock  = ${Function:Get-NonIpmSubtree}
            }

            # If we're not doing slow traversal, we can get the stats concurrently with the other jobs
            if (-not $SlowTraversal) {
                Add-JobQueueJob @{
                    ArgumentList = $serverName
                    Name         = "Get-ItemCount"
                    ScriptBlock  = ${Function:Get-ItemCount}
                }
            }

            $completedJobs = Wait-QueuedJob

            foreach ($job in $completedJobs) {
                if ($null -ne $job.IpmSubtree) {
                    $folderData.IpmSubtree = $job.IpmSubtree
                }

                if ($null -ne $job.NonIpmSubtree) {
                    $folderData.NonIpmSubtree = $job.NonIpmSubtree
                }

                if ($null -ne $job.ItemCounts) {
                    $folderData.ItemCounts = $job.ItemCounts
                }
            }

            # If we're doing slow traversal, we have to get the stats after we have the hierarchy
            if ($SlowTraversal) {
                $folderData.ItemCounts = Get-ItemCount $serverName $SlowTraversal
            }
        }

        $folderData.IpmSubtree | Export-Csv $PSScriptRoot\IpmSubtree.csv
        $folderData.NonIpmSubtree | Export-Csv $PSScriptRoot\NonIpmSubtree.csv
        $folderData.ItemCounts | Export-Csv $PSScriptRoot\ItemCounts.csv

        $folderData.IpmSubtreeByMailbox = $folderData.IpmSubtree | Group-Object ContentMailbox
        $folderData.IpmSubtree | ForEach-Object { $folderData.ParentEntryIdCounts[$_.ParentEntryId] += 1 }
        $folderData.IpmSubtree | ForEach-Object { $folderData.EntryIdDictionary[$_.EntryId] = $_ }
        $folderData.NonIpmSubtree | ForEach-Object { $folderData.NonIpmEntryIdDictionary[$_.EntryId] = $_ }
        $folderData.ItemCounts | ForEach-Object { $folderData.ItemCountDictionary[$_.EntryId] = $_.ItemCount }
    }

    end {
        Write-Host "Get-FolderData duration $((Get-Date) - $startTime)"
        Write-Host "    IPM_SUBTREE folder count: $($folderData.IpmSubtree.Count)"
        Write-Host "    NON_IPM_SUBTREE folder count: $($folderData.NonIpmSubtree.Count)"

        return $folderData
    }
}

. $PSScriptRoot\Get-IpmSubtree.ps1
. $PSScriptRoot\Get-NonIpmSubtree.ps1
. $PSScriptRoot\Get-ItemCount.ps1
