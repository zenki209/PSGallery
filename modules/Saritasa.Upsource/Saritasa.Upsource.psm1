

[string] $UpsourceUrl = ''
[pscredential] $UpsourceCredentials


<#
.SYNOPSIS
Returns collection of revisions which not exists in any review with revisionId, date, author and commit message.

.PARAMETER UpsourceUrl
Url of the Upsource without trailing slash.

.PARAMETER Credential
Credentials which will be used for Basic authentication when sending requests to Upsource.
#>
function Initialize-Upsource
{
    [CmdletBinding()]
    param
    (
        # Id of project, like 'crm'.
        [Parameter(Mandatory = $true)]
        [string] $UpsourceUrl,
        # Credentials which will be used for Basic authentication when sending requests to Upsource.
        [Parameter(Mandatory = $true)]
        [pscredential] $Credential
    )

    $script:UpsourceUrl = $UpsourceUrl
    $script:UpsourceCredentials = $Credential
}

<#
.SYNOPSIS
Converting time from response of Upsource which provide only milliseconds from Unix time.
#>
function ConvertTime
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string] $Milliseconds
    )

    $origin = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0
    $origin = $origin.AddMilliseconds($Milliseconds).ToLocalTime()

    $origin
}


<#
.SYNOPSIS
Encoding string value to base64.
#>
function EncodeBase64
{
    [OutputType('System.String')]
    param
    (
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    $textBytes = [System.Text.Encoding]::UTF8.GetBytes($value)

    $encodedText = [Convert]::ToBase64String($textBytes)

    $encodedText
}

<#
.SYNOPSIS
Encoding credentials for Basic authentication.
#>
function EncodeCredential
{
    $value = $UpsourceCredentials.UserName + ":" + $UpsourceCredentials.GetNetworkCredential().Password
    EncodeBase64 -Value $value
}

<#
.SYNOPSIS
Invoking REST web request to retrieve data.
#>
function InvokeWebRequest
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string] $Url,
        [Parameter(Mandatory = $true)]
        [string] $Body
    )

    $credentialsEncoded = EncodeCredential

    Invoke-RestMethod -ContentType 'application/json' -Headers @{'Authorization' = "Basic $credentialsEncoded"} `
        -Body $Body `
        -Method Post `
        -Uri $Url `
}

<#
.SYNOPSIS
Get information about revision.
#>
function GetRevisionInfo
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string] $ProjectId,
        [Parameter(Mandatory = $true)]
        [string] $RevisionId
    )

    $url = "$UpsourceUrl/~rpc/getRevisionInfo"

    $params = @{
        projectId  = $ProjectId
        revisionId = $RevisionId
    } | ConvertTo-Json

    InvokeWebRequest -Url $url -Body $params
}

<#
.SYNOPSIS
Get filtered revisions with filtering by 'Query' parameter.
#>
function GetRevision
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignment", "",
        Scope = "Function", Target = "*")]
    [OutputType('System.Object[]')]
    param
    (
        [Parameter(Mandatory = $true)]
        [string] $ProjectId,
        [int] $Limit = 30,
        [string] $Query
    )

    $requestDto = @{
        projectId    = $ProjectId
        limit        = $Limit
        query        = $Query
        requestGraph = $false
    } | ConvertTo-Json

    $url = "$UpsourceUrl/~rpc/getRevisionsListFiltered"

    $result = InvokeWebRequest -Url $url -Body $requestDto

    $revisionIds = $result.result.revision.revisionId
    $revisionIds
}

<#
.SYNOPSIS
Returns revisions in review.
#>
function GetRevisionInReview
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignment", "",
        Scope = "Function", Target = "*")]
    [OutputType('System.Object[]')]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ProjectId,
        [Parameter(Mandatory = $true)]
        [string]$ReviewId
    )

    $params = @{
        projectId = $ProjectId
        reviewId  = $ReviewId
    } | ConvertTo-Json

    $url = "$UpsourceUrl/~rpc/getRevisionsInReview"

    $result = InvokeWebRequest -Url $url -Body $params

    $revisionIds = $result.result.allRevisions.revision.revisionId
    $revisionIds
}

<#
.SYNOPSIS
Returns reviews in project.
#>
function GetReviewList
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignment", "",
        Scope = "Function", Target = "*")]
    [OutputType('System.Object[]')]
    param
    (
        [Parameter(Mandatory = $true)]
        [int] $Limit,
        [string] $Query,
        [string] $ProjectId
    )

    $url = "$UpsourceUrl/~rpc/getReviews"

    $reviewsRequestDto = @{
        limit     = $Limit
        query     = $Query
        projectId = $ProjectId
    } | ConvertTo-Json

    $result = InvokeWebRequest -Url $url -Body $reviewsRequestDto

    $reviewIds = $result.result.reviews.reviewId.reviewId
    $reviewIds
}

<#
.SYNOPSIS
Returns information about user.
#>
function GetUserInfo
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string[]] $UserIds
    )

    $url = "$UpsourceUrl/~rpc/getUserInfo"

    $params = @{
        ids = $UserIds
    } | ConvertTo-Json

    InvokeWebRequest -Url $url -Body $params
}

<#
.SYNOPSIS
Returns collection of revisions which not exists in any review with revisionId, date, author and commit message.

.PARAMETER ProjectId
Id of project, like 'crm'.

.PARAMETER Branch
Branch of project, by default it's a 'develop'.

.PARAMETER DaysLimit
Limit of days from 'now'.

.PARAMETER Stopwords
Words which will be searched in commit message and if it's include this words, that revision will be skipped.
#>
function Get-RevisionWithoutReview
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignment", "",
        Scope = "Function", Target = "*")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSPossibleIncorrectComparisonWithNull", "",
        Scope = "Function", Target = "*")]
    [OutputType('System.Object[]')]
    param
    (
        # Id of project, like 'crm'.
        [Parameter(Mandatory = $true)]
        [string] $ProjectId,
        # Branch of project, by default it's a 'develop'.
        [string] $Branch = 'develop',
        # Limit of days from 'now'.
        [int] $DaysLimit = 30,
        # Words which will be searched in commit message and if it's include this words, that revision will be skipped.
        [string[]] $Stopwords
    )

    [datetime]$now = [datetime]::Now
    $from = $now.Date.AddDays( - $DaysLimit)

    $endDateString = $now.ToString("yyyy-MMM-dd")
    $startDateString = $from.ToString("yyyy-MMM-dd")

    [string]$dateQuery = "created: $startDateString .. $endDateString or updated: $startDateString .. $endDateString"

    $branchQuery = "branch:$Branch and date:$startDateString .. $endDateString"

    $allRevisions = GetRevision -ProjectId $ProjectId -Limit 10000 -Query $branchQuery

    $allReviews = GetReviewList -ProjectId $ProjectId -Limit 100 -Query $dateQuery

    $revisionsInReviews = @()

    $allReviews | ForEach-Object `
    {
        if ($_ -ne $null -and $_ -ne [string]::Empty)
        {
            $revisionsInReview = GetRevisionInReview -ProjectId $ProjectId -ReviewId $_

            $revisionsInReview | ForEach-Object { $revisionsInReviews += $_ }
        }
    }

    $revisionsWithoutReview = @()

    $stopwordsFilter = $null
    if ($Stopwords -ne $null -and $Stopwords.Length -gt 0)
    {
        $stopwordsFilter = [string]::Join('|', $Stopwords)
    }

    $allRevisions | ForEach-Object `
    {
        if ($revisionsInReviews -notcontains $_ -and $_ -ne $null)
        {
            $revisionInfo = GetRevisionInfo -ProjectId $ProjectId -RevisionId $_

            $containsStopwords = $false

            if ($stopwordsFilter -ne $null)
            {
                if ($revisionInfo.result.revisionCommitMessage -match $stopwordsFilter)
                {
                    $containsStopwords = $true
                }
            }

            if (!$containsStopwords)
            {
                $revisionsWithoutReview += @{
                    Revision      = $revisionInfo.result.revisionId
                    Date          = ConvertTime -Milliseconds $revisionInfo.result.revisionDate
                    Author        = $revisionInfo.result.authorId
                    CommitMessage = $revisionInfo.result.revisionCommitMessage
                }
            }
        }
    }

    $userIds = @()

    $revisionsWithoutReview | ForEach-Object `
    {
        if ($userIds -notcontains $_.Author -and $_.Author -ne $null)
        {
            $userIds += ([string]$_.Author).Trim()
        }
    }

    # Replace user IDs with their names.
    if ($userIds.Length -gt 0)
    {
        $userInfos = GetUserInfo -UserIds $userIds

        $userInfos.result.infos | ForEach-Object `
        {
            $info = $_

            $revisionsWithoutReview | ForEach-Object `
            {
                if ($_.Author -eq $info.userId)
                {
                    $_.Author = $info.name
                }
            }
        }
    }

    $revisionsWithoutReview
}