# Kubernetes Deployment Script for Persons Finder
# Prerequisites: kubectl configured, K8s cluster running, image built and available

param(
    [string]$Namespace = "default",
    [string]$ImageTag = "0.0.1"
)

$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

# Color output helper
function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Pause-For-User {
    param([string]$Message = "Press Enter to continue...")
    Write-Host ""
    Write-Host $Message -ForegroundColor Magenta
    Read-Host | Out-Null
    Write-Host ""
}

# Main script
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "Kubernetes Deployment: Persons Finder" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# ==========================================
# Step 1: Verify kubectl and cluster access
# ==========================================
Write-Info "Step 1/5: Verifying kubectl and cluster access..."
try {
    $clusterInfo = kubectl cluster-info 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl not configured or cluster not accessible"
    }
    Write-Success "kubectl is configured and cluster is accessible"
    Write-Info "Cluster info: $(($clusterInfo | Select-Object -First 1))"
} catch {
    Write-Error-Custom "Failed to access cluster: $_"
    Write-Host "Please configure kubectl and ensure your cluster is running."
    exit 1
}

Pause-For-User "Review cluster info above. Press Enter to continue..."

# ==========================================
# Step 2: Get OPENAI_API_KEY from user
# ==========================================
Write-Info "Step 2/5: Retrieving OPENAI_API_KEY..."
Write-Host ""
Write-Host "Enter your OpenAI API Key (input will be hidden):" -ForegroundColor Yellow
$apiKeySecure = Read-Host -AsSecureString

# Safely convert secure string
if ($apiKeySecure.Length -eq 0) {
    Write-Error-Custom "API Key cannot be empty"
    exit 1
}

$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($apiKeySecure)
try {
    $apiKeyPlaintext = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
} finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
}

if ([string]::IsNullOrWhiteSpace($apiKeyPlaintext)) {
    Write-Error-Custom "Failed to convert API Key"
    exit 1
}

Write-Success "API Key received (will be stored in K8s Secret)"
Write-Info "Creating/updating Secret: persons-finder-secret"
Write-Host ""

Pause-For-User "Press Enter to create the Secret with your API Key..."

# ==========================================
# Step 3: Create/Update the Secret
# ==========================================
try {
    # Create secret via kubectl (this way we don't expose key in a file)
    Write-Info "Creating Kubernetes Secret: persons-finder-secret"
    
    # Split into two commands to properly check exit code
    $secretYaml = kubectl create secret generic persons-finder-secret `
        --from-literal=openai-api-key="$apiKeyPlaintext" `
        --namespace=$Namespace `
        --dry-run=client -o yaml 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to generate secret YAML: $secretYaml"
    }
    
    # Apply the secret
    $secretYaml | kubectl apply -f - 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Secret 'persons-finder-secret' created/updated"
    } else {
        throw "Failed to apply secret"
    }
} catch {
    Write-Error-Custom "Error creating secret: $_"
    exit 1
}

Pause-For-User "Secret created. Press Enter to deploy manifests..."

# ==========================================
# Step 4: Deploy all Kubernetes manifests
# ==========================================
Write-Info "Step 4/5: Deploying Kubernetes manifests..."
Write-Host ""

$manifestDir = "k8s"
$manifests = @(
    "01-secret.yaml",
    "02-service.yaml",
    "03-deployment.yaml",
    "04-ingress.yaml",
    "05-hpa.yaml",
    "06-serviceaccount.yaml",
    "07-poddisruptionbudget.yaml"
)

$failedManifests = @()

foreach ($manifest in $manifests) {
    $manifestPath = Join-Path $manifestDir $manifest
    
    if (-not (Test-Path $manifestPath)) {
        Write-Warning-Custom "Manifest not found: $manifestPath (skipping)"
        continue
    }
    
    Write-Info "Applying: $manifest"
    try {
        kubectl apply -f $manifestPath --namespace=$Namespace | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Applied: $manifest"
        } else {
            Write-Error-Custom "Failed to apply: $manifest"
            $failedManifests += $manifest
        }
    } catch {
        Write-Error-Custom "Error applying $($manifest): $($_)"
        $failedManifests += $manifest
    }
}

Write-Host ""

if ($failedManifests.Count -gt 0) {
    Write-Warning-Custom "Some manifests failed to deploy:"
    $failedManifests | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""
    $response = Read-Host "Continue with verification despite failures? (y/n)"
    if ($response -ne "y") {
        exit 1
    }
}

Pause-For-User "Manifests deployed. Press Enter to verify deployment..."

# ==========================================
# Step 5: Verify Deployment
# ==========================================
Write-Info "Step 5/5: Verifying Kubernetes deployment..."
Write-Host ""

try {
    # Check Deployment
    Write-Info "Checking Deployment status..."
    $deploymentJson = kubectl get deployment persons-finder -n $Namespace -o json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Warning-Custom "Deployment not found or error: $deploymentJson"
    } else {
        $deployment = $deploymentJson | ConvertFrom-Json
        $readyReplicas = $deployment.status.readyReplicas -as [int] -or 0
        $desiredReplicas = $deployment.spec.replicas
        
        Write-Host "Deployment: persons-finder"
        Write-Host "  Ready Replicas: $readyReplicas / $desiredReplicas"
        
        if ($readyReplicas -ge 1) {
            Write-Success "Deployment is healthy"
        } else {
            Write-Warning-Custom "Deployment not yet ready (waiting for pods to start)"
        }
    }
    
    Write-Host ""
    
    # Check Pods
    Write-Info "Checking Pod status..."
    $podsJson = kubectl get pods -l app=persons-finder -n $Namespace -o json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Warning-Custom "Error retrieving pods: $podsJson"
    } else {
        $pods = $podsJson | ConvertFrom-Json
        # PowerShell quirk: .Count on single item returns $null, use @(...).Count instead
        $podCount = @($pods.items).Count
        
        if ($podCount -gt 0) {
            Write-Success "Found $podCount pod(s)"
            @($pods.items) | ForEach-Object {
                $podName = $_.metadata.name
                $phase = $_.status.phase
                $ready = $_.status.conditions | Where-Object { $_.type -eq "Ready" } | Select-Object -ExpandProperty status
                Write-Host "  - $podName : $phase (Ready: $ready)"
            }
        } else {
            Write-Warning-Custom "No pods found yet (deployment may still be initializing)"
        }
    }
    
    Write-Host ""
    
    # Check Service
    Write-Info "Checking Service..."
    $serviceJson = kubectl get svc persons-finder -n $Namespace -o json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Warning-Custom "Service not found: $serviceJson"
    } else {
        $service = $serviceJson | ConvertFrom-Json
        $clusterIP = $service.spec.clusterIP
        Write-Success "Service: persons-finder (Cluster IP: $clusterIP)"
    }
    
    Write-Host ""
    
    # Check Secret
    Write-Info "Checking Secret..."
    $secretExists = kubectl get secret persons-finder-secret -n $Namespace 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Secret: persons-finder-secret exists"
    } else {
        Write-Error-Custom "Secret: persons-finder-secret not found"
    }
    
    Write-Host ""
    
    # Check HPA
    Write-Info "Checking Horizontal Pod Autoscaler..."
    $hpaJson = kubectl get hpa persons-finder-hpa -n $Namespace -o json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        try {
            $hpa = $hpaJson | ConvertFrom-Json
            $minReplicas = $hpa.spec.minReplicas
            $maxReplicas = $hpa.spec.maxReplicas
            Write-Success "HPA: persons-finder-hpa (Min: $minReplicas, Max: $maxReplicas)"
        } catch {
            Write-Warning-Custom "Error parsing HPA: $_"
        }
    } else {
        Write-Warning-Custom "HPA not found"
    }
    
    Write-Host ""
    
    # Check PDB
    Write-Info "Checking Pod Disruption Budget..."
    $pdbJson = kubectl get pdb persons-finder-pdb -n $Namespace -o json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        try {
            $pdb = $pdbJson | ConvertFrom-Json
            $minAvailable = $pdb.spec.minAvailable
            Write-Success "PDB: persons-finder-pdb (minAvailable: $minAvailable)"
        } catch {
            Write-Warning-Custom "Error parsing PDB: $_"
        }
    } else {
        Write-Warning-Custom "PDB not found"
    }
    
} catch {
    Write-Error-Custom "Error during verification: $_"
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Info "Next steps:"
Write-Host "1. Wait for all pods to be Ready (kubectl get pods -l app=persons-finder)"
Write-Host "2. Port-forward to test locally:"
Write-Host "   kubectl port-forward svc/persons-finder 8080:80 -n $Namespace"
Write-Host "3. Call the API:"
Write-Host "   curl http://localhost:8080/api/v1/persons"
Write-Host ""

Pause-For-User "Press Enter to exit."
