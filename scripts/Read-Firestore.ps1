param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectId,

    [Parameter(Mandatory = $true)]
    [string]$CollectionPath,

    [string]$DocumentId,
    [string]$DatabaseId = "(default)",
    [int]$PageSize = 25,
    [string]$CredentialsPath = $env:GOOGLE_APPLICATION_CREDENTIALS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "read-firestore.mjs"

$arguments = @(
    $scriptPath,
    "--projectId", $ProjectId,
    "--collectionPath", $CollectionPath,
    "--databaseId", $DatabaseId,
    "--pageSize", $PageSize.ToString()
)

if ($DocumentId) {
    $arguments += @("--documentId", $DocumentId)
}

if ($CredentialsPath) {
    $arguments += @("--credentialsPath", $CredentialsPath)
}

& node @arguments
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
