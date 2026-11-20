[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

$envFile = Join-Path $ProjectRoot '.env'
if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    throw "Local .env file not found. From the project root, copy .env.example to .env and set the required values."
}

foreach ($line in (Get-Content -LiteralPath $envFile -ErrorAction Stop)) {
    $text = ([string]$line).Trim()
    if ([string]::IsNullOrWhiteSpace($text) -or $text.StartsWith('#')) { continue }
    if ($text -notmatch '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') { continue }

    $name = $Matches[1]
    $value = $Matches[2].Trim()
    if ($value.Length -ge 2) {
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
    }

    # Explicit process-level environment variables take precedence over .env.
    $existing = [Environment]::GetEnvironmentVariable($name, 'Process')
    if ([string]::IsNullOrEmpty($existing)) {
        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }
}
