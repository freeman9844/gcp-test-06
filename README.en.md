# GKE Gateway API Sample Application

[한국어 (Korean)](README.md) | **English**

This project demonstrates how to deploy a scalable, secure web application on Google Kubernetes Engine (GKE) Autopilot using the **Gateway API**. It includes a sample Go application and a complete set of Kubernetes manifests to configure a Global External Application Load Balancer with advanced features like Cloud Armor, SSL Policies, and Certificate Manager.

## Architecture

The deployment consists of the following components:

-   **Sample Application**: A simple Go HTTP server exposing `/` and `/healthz` endpoints.
-   **GKE Autopilot**: The managed Kubernetes environment hosting the application.
-   **Gateway (GKE L7 Global External Managed)**: Entry point for traffic, handling routing and termination.
-   **Certificate Manager (Cert Map)**: Manages SSL certificates efficiently (using `test01-com-map`).
-   **Cloud Armor**: Provides DDoS protection and security policies (using `armor-sad-gas`).
-   **SSL Policy**: Enforces TLS security standards (using `ssl-policy-tls-1-2`).
-   **HTTPRoutes**:
    -   `openfga-http-route`: Redirects HTTP (port 80) traffic to HTTPS.
    -   `openfga-https-route`: Routes HTTPS (port 443) traffic to the backend service.

## Prerequisites

Before deploying, ensure you have the following Google Cloud resources created:

1.  **GKE Cluster**: An Autopilot or Standard cluster (e.g., `autopilot-cluster-1`).
2.  **Global Static IP**: A reserved IP address named `openfga-gke1-sad-01`.
    ```bash
    gcloud compute addresses create openfga-gke1-sad-01 --global
    ```
3.  **Certificate Map**: A Certificate Map named `test01-com-map` containing your certificates.
4.  **Cloud Armor Policy**: A security policy named `armor-sad-gas`.
    ```bash
    gcloud compute security-policies create armor-sad-gas --description "Default policy" --global
    ```
5.  **SSL Policy**: An SSL policy named `ssl-policy-tls-1-2`.
    ```bash
    gcloud compute ssl-policies create ssl-policy-tls-1-2 --profile COMPATIBLE --min-tls-version 1.2 --global
    ```

## Certificate Manager Setup (Reference)

If you need to create a self-signed certificate and configuring Certificate Manager from scratch, follow these steps:

### 1. Generate Self-Signed Certificate

Create a configuration file `openssl.cnf`:

```bash
cat <<'EOF' >openssl.cnf
[req]
default_bits              = 2048
req_extensions            = extension_requirements
distinguished_name        = dn_requirements
prompt                    = no

[extension_requirements]
basicConstraints          = CA:FALSE
keyUsage                  = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName            = @sans_list

[dn_requirements]
countryName               = KR
stateOrProvinceName       = State or Province Name (full name)
localityName              = Locality Name (eg, city)
0.organizationName        = Organization Name (eg, company)
organizationalUnitName    = Organizational Unit Name (eg, section)
commonName                = test01.com
emailAddress              = jungwoonlee@google.com

[sans_list]
DNS.1                     = *.test01.com
DNS.2                     = test01.com
DNS.3                     = test.test01.com
EOF
```

Generate the key and certificate:

```bash
# Generate private key
openssl genrsa -out key.pem 2048

# Generate CSR
openssl req -new -key key.pem \
    -out csr.pem \
    -config openssl.cnf

# Sign Certificate
openssl x509 -req \
    -signkey key.pem \
    -in csr.pem \
    -out cert.pem \
    -extfile openssl.cnf \
    -extensions extension_requirements \
    -days 3650
```

### 2. Configure Google Cloud Certificate Manager

Upload the certificate and create the map entry:

```bash
# Create Certificate resource
gcloud certificate-manager certificates create test01-com-cert \
    --certificate-file="cert.pem" \
    --private-key-file="key.pem"

# Create Certificate Map
gcloud certificate-manager maps create test01-com-map

# Create Map Entry
gcloud certificate-manager maps entries create test01-com-map-entry \
    --map=test01-com-map \
    --hostname=*.test01.com \
    --certificates=test01-com-cert
```

## Project Structure

```
.
├── Dockerfile                  # Build instructions for the Go app
├── go.mod                      # Go module definition
├── main.go                     # Application source code
└── manifests/                  # Kubernetes configuration
    ├── deployment.yaml         # App Deployment
    ├── service.yaml            # App Service (ClusterIP)
    ├── gateway.yaml            # Gateway definition (Listener & CertMap config)
    ├── gcpgatewaypolicy.yaml   # Attaches SSL Policy to Gateway
    ├── gcpbackendpolicy.yaml   # Attaches Cloud Armor to Service
    ├── healthcheck.yaml        # Custom HealthCheck configuration
    ├── httproute-https.yaml    # HTTPS routing rules
    └── httproute-http-redirect.yaml # HTTP to HTTPS redirect rules
```

## Deployment

1.  **Build and Push the Container Image**:
    ```bash
    gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/openfga-sample:v1 .
    ```
    *Note: Update `deployment.yaml` if you change the image tag.*

2.  **Apply Kubernetes Manifests**:
    ```bash
    kubectl apply -f manifests/
    ```

## Verification

To verify the deployment, you can use `curl` to test connectivity through the Gateway's global IP or a mapped hostname.

1.  **Check Resources**:
    ```bash
    kubectl get gateway,httproute,service,gcpbackendpolicy -n test01
    ```

2.  **Test HTTP Redirect**:
    ```bash
    # Replace aaa.test01.com with your hostname and IP with your Global IP
    curl -v http://aaa.test01.com/
    ```
    *Expected output: `301 Moved Permanently` redirecting to HTTPS.*

3.  **Test HTTPS Access**:
    ```bash
    curl -v https://aaa.test01.com/
    ```
    *Expected output: `200 OK` with body `Hello from OpenFGA Sample`.*
