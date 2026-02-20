# Kubernetes Manifests for Persons Finder

This directory contains production-ready Kubernetes manifests for deploying the Persons Finder Spring Boot application.

## Files Overview

### 01-secret.yaml
- **Type:** Secret (Opaque)
- **Purpose:** Stores the OPENAI_API_KEY securely
- **Usage:** Referenced by Deployment as environment variable
- **Security:** Never commit actual API key; use a Kubernetes secret management tool (Vault, AWS Secrets Manager, etc.)

### 02-service.yaml
- **Type:** Service (ClusterIP)
- **Purpose:** Exposes the application internally within the cluster
- **Port:** 80 (service) → 8080 (container)
- **Selector:** `app: persons-finder`

### 03-deployment.yaml
- **Type:** Deployment
- **Replicas:** 2 (default; scales via HPA)
- **Key Features:**
  - **Security Context:** Non-root user (UID 1000), read-only filesystem where possible
  - **Health Checks:** Liveness + Readiness probes on `/api/v1/persons`
  - **Resource Limits:** CPU 500m / Memory 512m; Requests CPU 100m / Memory 256m
  - **Graceful Shutdown:** 30s termination grace period with pre-stop sleep
  - **Pod Anti-Affinity:** Spreads replicas across nodes for high availability
  - **Environment Variables:** OPENAI_API_KEY from Secret, JVM options, port configuration

### 04-ingress.yaml
- **Type:** Ingress (nginx controller)
- **Host:** `persons-finder.local` (change as needed)
- **Path:** `/` (all traffic routed to service)
- **Annotations:** Nginx-specific settings (CORS, rate limiting, proxy body size)
- **TLS:** Commented out; uncomment and provide a certificate Secret when ready

### 05-hpa.yaml
- **Type:** HorizontalPodAutoscaler (v2)
- **Scaling Policy:**
  - Min replicas: 2
  - Max replicas: 5
  - CPU target: 70% utilization
  - Memory target: 80% utilization
- **Behavior:** Fast scale-up, gradual scale-down for stability

### 06-serviceaccount.yaml
- **Type:** ServiceAccount
- **Purpose:** Identity for RBAC (Role-Based Access Control)
- **Used By:** Deployment for pod identity (optional for this app, but good practice)

---

## Deployment Instructions

### Prerequisites
- Kubernetes cluster (Minikube, Kind, EKS, GKE, AKS, etc.)
- `kubectl` CLI configured to access the cluster
- Docker image `persons-finder:0.0.1` pushed to a registry or available locally

### Step 1: Update the Secret with Your API Key
Edit `01-secret.yaml` and replace the placeholder:

```bash
kubectl apply -f 01-secret.yaml
```

Or use `kubectl create secret`:

```bash
kubectl create secret generic persons-finder-secrets \
  --from-literal=OPENAI_API_KEY="your-actual-api-key" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 2: Apply All Manifests
```bash
kubectl apply -f k8s/
```

Or in order:
```bash
kubectl apply -f k8s/01-secret.yaml
kubectl apply -f k8s/02-service.yaml
kubectl apply -f k8s/03-deployment.yaml
kubectl apply -f k8s/04-ingress.yaml
kubectl apply -f k8s/05-hpa.yaml
kubectl apply -f k8s/06-serviceaccount.yaml
```

### Step 3: Verify Deployment
```bash
# Check deployment status
kubectl get deployments persons-finder

# Check pods
kubectl get pods -l app=persons-finder

# Check service
kubectl get svc persons-finder

# Check ingress
kubectl get ingress persons-finder

# View pod logs
kubectl logs -l app=persons-finder --tail=50
```

### Step 4: Test the Application
```bash
# Port-forward to access locally (if not using Ingress)
kubectl port-forward svc/persons-finder 8080:80

# Then call the API
curl http://localhost:8080/api/v1/persons
```

Or via Ingress (after Nginx Ingress controller is installed):
```bash
# Update /etc/hosts (or equivalent on Windows)
# 127.0.0.1 persons-finder.local

curl http://persons-finder.local/api/v1/persons
```

---

## Security Considerations

1. **OPENAI_API_KEY Secret:**
   - Use `kubectl create secret` with actual key, do **NOT** commit to version control
   - Consider rotating the key periodically
   - Use a secret management solution (HashiCorp Vault, AWS Secrets Manager, etc.)

2. **Network Policies:**
   - Add NetworkPolicy manifests to restrict ingress/egress traffic
   - Isolate the namespace

3. **RBAC:**
   - Create Role/RoleBinding for the ServiceAccount (example provided separately)
   - Restrict permissions to minimum required

4. **Pod Security Policies / Pod Security Standards:**
   - Enforce `restricted` PSP or PSS via namespace labels
   - Current Deployment already uses `runAsNonRoot`, `allowPrivilegeEscalation: false`

5. **TLS for Ingress:**
   - Uncomment the `tls` section in `04-ingress.yaml`
   - Create or reference a TLS certificate Secret
   - Use a cert manager (cert-manager.io) for automatic certificate provisioning

---

## Scaling & Performance

### Horizontal Pod Autoscaler (HPA)
The `05-hpa.yaml` manifest scales the deployment based on:
- **CPU utilization:** 70% threshold → up to 5 replicas
- **Memory utilization:** 80% threshold → up to 5 replicas

Monitor via:
```bash
kubectl get hpa persons-finder --watch
```

### Resource Requests & Limits
- **Requests:** CPU 100m, Memory 256m (guaranteed minimum)
- **Limits:** CPU 500m, Memory 512m (hard ceiling)

Adjust based on actual workload profiling.

---

## Health Checks

### Liveness Probe
- **Endpoint:** `GET /api/v1/persons`
- **Initial Delay:** 30s
- **Period:** 10s
- **Timeout:** 5s
- **Failure Threshold:** 3

Restarts pod if probe fails 3 times.

### Readiness Probe
- **Endpoint:** `GET /api/v1/persons`
- **Initial Delay:** 10s
- **Period:** 5s
- **Timeout:** 3s
- **Failure Threshold:** 2

Removes pod from load balancer if probe fails 2 times (recovers when healthy).

---

## Troubleshooting

### Pod stays in `Pending`
```bash
kubectl describe pod <pod-name>
# Check node resources and affinity constraints
```

### Pod crashes (CrashLoopBackOff)
```bash
kubectl logs <pod-name> --previous
# Check application startup logs and environment variables
```

### Image pull errors
```bash
# Ensure image is available in the registry or local Docker daemon
docker images | grep persons-finder
```

### API endpoint not responding
```bash
# Check pod readiness
kubectl get pods -l app=persons-finder

# Port-forward and test locally
kubectl port-forward pod/<pod-name> 8080:8080
curl http://localhost:8080/api/v1/persons
```

---

## Clean Up

To remove all resources:
```bash
kubectl delete -f k8s/

# Or selectively:
kubectl delete secret persons-finder-secrets
kubectl delete deployment persons-finder
kubectl delete service persons-finder
kubectl delete ingress persons-finder
kubectl delete hpa persons-finder-hpa
kubectl delete sa persons-finder
```

---

## Further Improvements (Optional)

1. **PersistentVolumes:** For stateful data (if needed)
2. **ConfigMaps:** For non-secret configuration
3. **NetworkPolicies:** Restrict pod-to-pod and pod-to-external communication
4. **Pod Disruption Budgets (PDB):** Govern voluntary disruptions during maintenance
5. **Vertical Pod Autoscaler (VPA):** Recommend resource sizing
6. **Monitoring & Logging:** Prometheus, Grafana, ELK, Datadog, etc.
7. **Service Mesh:** Istio, Linkerd for advanced traffic management
