# Check Docker
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker not installed. Install from https://docs.docker.com/get-docker/"
    exit 1
}

# Check port 80
$portTest = Test-NetConnection -ComputerName localhost -Port 80 -WarningAction SilentlyContinue
if ($portTest.TcpTestSucceeded) {
    Write-Warning "Something already listening on port 80 -- Let's Encrypt HTTP-01 may fail"
} else {
    Write-Host "Note: port 80 must be open on your firewall for Let's Encrypt to issue certificates"
}

# Detect public IP (IPv4 only — sslip.io requires IPv4)
try {
    $TraefikHost = "dusty-utility.$((Invoke-WebRequest -Uri 'https://api4.ipify.org' -UseBasicParsing).Content.Trim()).sslip.io"
} catch {
    try {
        $TraefikHost = "dusty-utility.$((Invoke-WebRequest -Uri 'https://ipv4.icanhazip.com' -UseBasicParsing).Content.Trim()).sslip.io"
    } catch {
        Write-Error "Error: could not detect public IPv4 address"; exit 1
    }
}
Write-Host "Domain: $TraefikHost"

# Create traefik-net if not exists
docker network create traefik-net 2>$null

# Inject TRAEFIK_HOST and ACME_EMAIL into each service .env
Get-ChildItem -Directory | ForEach-Object {
    $svcDir = $_.Name
    $envExample = "$svcDir\.env.example"
    $envFile = "$svcDir\.env"
    if (-not (Test-Path $envExample)) { return }
    if (-not (Test-Path $envFile)) { Copy-Item $envExample $envFile }
    $content = Get-Content $envFile
    if ($content -match "^TRAEFIK_HOST=") {
        $content = $content -replace "^TRAEFIK_HOST=.*", "TRAEFIK_HOST=$TraefikHost"
    }
    if ($content -match "^ACME_EMAIL=") {
        $content = $content -replace "^ACME_EMAIL=.*", "ACME_EMAIL=dl97.app@gmail.com"
    }
    $content | Set-Content $envFile
}

# Create acme.json (required by Traefik)
New-Item -ItemType File -Force acme.json | Out-Null

# Launch
./start.sh

Write-Host ""
Write-Host "Your app is live at: https://dusty-utility.<IPv4>.sslip.io"
Write-Host "Note: SSL certificate issuance takes ~30 seconds after startup"
