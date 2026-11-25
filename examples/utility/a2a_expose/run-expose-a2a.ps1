#Requires -Version 7.0
# Build the image. Run the A2A exposure script in the container.
[CmdletBinding()]
param(
    [string]$Context,
    [string]$Kubeconfig = $(if ($env:KUBECONFIG_PATH) { $env:KUBECONFIG_PATH } elseif ($env:KUBECONFIG) { $env:KUBECONFIG } else { Join-Path $HOME '.kube/config' }),
    [string]$ImageName = $(if ($env:RAM_A2A_IMAGE) { $env:RAM_A2A_IMAGE } else { 'ram-a2a-expose:local' }),
    [string]$Namespace = 'retagentmgr',
    [string]$RamUrl,
    [string]$Authorization = $env:RAM_AUTHORIZATION,
    [string]$KeycloakUrl,
    [string]$KeycloakRealm = 'sas-iot',
    [string]$KeycloakClientId = 'sas-ram-api',
    [string]$CaCert = $env:RAM_CA_CERT,
    [string]$AgentId,
    [ValidateSet('ingress', 'httpproxy')][string]$Mode,
    [string]$PublicBaseUrl,
    [string]$BasePath = '/SASRetrievalAgentManager',
    [string]$HttpProxyName = 'retrieval-agent-manager-ingress',
    [string]$ExtensionNamespace,
    [string]$IngressClassName,
    [string]$TlsSecretName,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 60,
    [switch]$ListOnly,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
foreach ($name in @('docker', 'kubectl')) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "$name is required." }
}
if (-not (Test-Path -LiteralPath $Kubeconfig -PathType Leaf)) {
    throw 'Use one existing Kubernetes configuration file.'
}
$configPath = (Resolve-Path -LiteralPath $Kubeconfig).Path
$certificatePath = $null
if ($CaCert) {
    if (-not (Test-Path -LiteralPath $CaCert -PathType Leaf)) { throw 'The CA certificate bundle must be a file.' }
    $certificatePath = (Resolve-Path -LiteralPath $CaCert).Path
}
if (-not $Context) {
    $contexts = @(& kubectl --kubeconfig $configPath config get-contexts -o name)
    if ($LASTEXITCODE -ne 0) { throw 'Could not list Kubernetes contexts.' }
    if ($contexts.Count -eq 0) { throw 'No Kubernetes contexts are available.' }
    if ($contexts.Count -eq 1) {
        $Context = $contexts[0]
    } else {
        for ($i = 0; $i -lt $contexts.Count; $i++) { Write-Host "$($i + 1). $($contexts[$i])" }
        do {
            $number = 0
            $answer = Read-Host 'Select a Kubernetes context number'
            if ($null -eq $answer) { throw 'A context selection is required. Supply -Context when input is not available.' }
            $valid = [int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $contexts.Count
            if (-not $valid) { Write-Host 'The selection is not valid. Select a number from the list.' }
        } until ($valid)
        $Context = $contexts[$number - 1]
    }
}
& docker info *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker is not available.' }

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ('ram-a2a-' + [guid]::NewGuid())
$runtimeConfig = Join-Path $temporaryDirectory 'config.json'
$previousAuthorization = [Environment]::GetEnvironmentVariable('RAM_AUTHORIZATION')
try {
    $null = New-Item -ItemType Directory -Path $temporaryDirectory
    if ($IsWindows) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $access = [Security.AccessControl.DirectorySecurity]::new()
        $access.SetAccessRuleProtection($true, $false)
        $access.SetOwner($identity)
        $access.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        Set-Acl -LiteralPath $temporaryDirectory -AclObject $access
    } else {
        & chmod 700 $temporaryDirectory
        if ($LASTEXITCODE -ne 0) { throw 'Could not protect the temporary directory.' }
    }
    $rawConfig = & kubectl --kubeconfig $configPath --context $Context config view --raw --flatten --minify -o json
    if ($LASTEXITCODE -ne 0) { throw "Could not read Kubernetes context $Context." }
    $configuration = ($rawConfig -join "`n") | ConvertFrom-Json -AsHashtable
    if ($configuration.contexts.Count -ne 1 -or $configuration.contexts[0].name -cne $Context) {
        throw 'The Kubernetes configuration does not match the selected context.'
    }
    foreach ($entry in @($configuration.users)) {
        $user = $entry.user
        if ($user.Contains('exec')) {
            $command = [IO.Path]::GetFileNameWithoutExtension($user.exec.command)
            if ($command -ne 'kubelogin') {
                throw "The container cannot run Kubernetes login command $command."
            }
            $loginArgs = @($user.exec.args)
            $loginIndex = [Array]::IndexOf($loginArgs, '--login')
            if ($loginIndex -ge 0 -and $loginIndex + 1 -lt $loginArgs.Count -and $loginArgs[$loginIndex + 1] -eq 'azurecli') {
                foreach ($name in @('az', 'kubelogin')) {
                    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "$name is required for this context." }
                }
                $response = & kubelogin @loginArgs
                if ($LASTEXITCODE -ne 0) { throw 'Could not get the Kubernetes access token.' }
                $credential = ($response -join "`n") | ConvertFrom-Json -AsHashtable
                if (-not $credential.status.token) { throw 'The Kubernetes access token is empty.' }
                $user.Remove('exec')
                $user.Remove('auth-provider')
                $user.token = $credential.status.token
            } else {
                $user.exec.command = 'kubelogin'
            }
        }
    }
    $configuration | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $runtimeConfig -Encoding utf8NoBOM
    & docker build --tag $ImageName $PSScriptRoot
    if ($LASTEXITCODE -ne 0) { throw 'The Docker image build failed.' }
    $runArguments = @('run', '--rm', '--interactive', '--network', 'host')
    if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) { $runArguments += '--tty' }
    $runArguments += @('--volume', "${runtimeConfig}:/root/.kube/config:ro", '--env', 'KUBECONFIG=/root/.kube/config')
    if ($certificatePath) { $runArguments += @('--volume', "${certificatePath}:/opt/ram-a2a/ca.pem:ro") }
    [Environment]::SetEnvironmentVariable('RAM_AUTHORIZATION', $Authorization)
    foreach ($name in @('RAM_AUTHORIZATION', 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'no_proxy')) {
        if ($null -ne [Environment]::GetEnvironmentVariable($name)) { $runArguments += @('--env', $name) }
    }
    $runArguments += @($ImageName, '--context', $Context, '--namespace', $Namespace,
        '--http-proxy-name', $HttpProxyName, '--timeout-seconds', "$TimeoutSeconds")
    if ($PSBoundParameters.ContainsKey('BasePath')) { $runArguments += @('--base-path', $BasePath) }
    foreach ($setting in @(
        @('--ram-url', $RamUrl), @('--agent-id', $AgentId), @('--mode', $Mode),
        @('--public-base-url', $PublicBaseUrl), @('--extension-namespace', $ExtensionNamespace),
        @('--ingress-class-name', $IngressClassName), @('--tls-secret-name', $TlsSecretName),
        @('--keycloak-url', $KeycloakUrl), @('--keycloak-realm', $KeycloakRealm),
        @('--keycloak-client-id', $KeycloakClientId)
    )) {
        if ($setting[1]) { $runArguments += $setting }
    }
    if ($certificatePath) { $runArguments += @('--ca-cert', '/opt/ram-a2a/ca.pem') }
    if ($ListOnly) { $runArguments += '--list-only' }
    if ($DryRun) { $runArguments += '--dry-run' }
    & docker @runArguments
    if ($LASTEXITCODE -ne 0) { throw "The A2A exposure container failed (exit $LASTEXITCODE)." }
} finally {
    if ($null -eq $previousAuthorization) {
        if (Test-Path Env:RAM_AUTHORIZATION) { Remove-Item Env:RAM_AUTHORIZATION }
    } else {
        [Environment]::SetEnvironmentVariable('RAM_AUTHORIZATION', $previousAuthorization)
    }
    if (Test-Path -LiteralPath $runtimeConfig) { Remove-Item -LiteralPath $runtimeConfig -Force }
    if (Test-Path -LiteralPath $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory }
}
