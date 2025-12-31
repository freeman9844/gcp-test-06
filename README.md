# GKE Gateway API 샘플 애플리케이션

**한국어 (Korean)** | [English](README.en.md)

이 프로젝트는 **Gateway API**를 사용하여 Google Kubernetes Engine (GKE) Autopilot에 확장 가능하고 안전한 웹 애플리케이션을 배포하는 방법을 보여줍니다. 여기에는 샘플 Go 애플리케이션과 Cloud Armor, SSL 정책, Certificate Manager와 같은 고급 기능을 갖춘 Global External Application Load Balancer를 구성하기 위한 전체 Kubernetes 매니페스트 세트가 포함되어 있습니다.

## 아키텍처

배포는 다음 구성 요소로 이루어집니다:

-   **샘플 애플리케이션**: `/` 및 `/healthz` 엔드포인트를 노출하는 간단한 Go HTTP 서버.
-   **GKE Autopilot**: 애플리케이션을 호스팅하는 관리형 Kubernetes 환경.
-   **Gateway (GKE L7 Global External Managed)**: 트래픽 진입점으로, 라우팅 및 SSL 종료를 처리.
-   **Certificate Manager (Cert Map)**: SSL 인증서를 효율적으로 관리 (`test01-com-map` 사용).
-   **Cloud Armor**: DDoS 보호 및 보안 정책 제공 (`armor-sad-gas` 사용).
-   **SSL 정책**: TLS 보안 표준 강제 (`ssl-policy-tls-1-2` 사용).
-   **HTTPRoutes**:
    -   `openfga-http-route`: HTTP (포트 80) 트래픽을 HTTPS로 리다이렉트.
    -   `openfga-https-route`: HTTPS (포트 443) 트래픽을 백엔드 서비스로 라우팅.

## 사전 요구 사항

배포하기 전에 다음 Google Cloud 리소스가 생성되어 있는지 확인하세요:

1.  **GKE 클러스터**: Autopilot 또는 Standard 클러스터 (예: `autopilot-cluster-1`).
2.  **전역 고정 IP**: `openfga-gke1-sad-01`이라는 이름의 예약된 IP 주소.
    ```bash
    gcloud compute addresses create openfga-gke1-sad-01 --global
    ```
3.  **Certificate Map**: 인증서를 포함하는 `test01-com-map`이라는 Certificate Map.
4.  **Cloud Armor 정책**: `armor-sad-gas`라는 보안 정책.
    ```bash
    gcloud compute security-policies create armor-sad-gas --description "Default policy" --global
    ```
5.  **SSL 정책**: `ssl-policy-tls-1-2`라는 SSL 정책.
    ```bash
    gcloud compute ssl-policies create ssl-policy-tls-1-2 --profile COMPATIBLE --min-tls-version 1.2 --global
    ```

## Certificate Manager 설정 (참고)

자체 서명된 인증서를 생성하고 처음부터 Certificate Manager를 구성해야 하는 경우 다음 단계를 따르세요:

### 1. 자체 서명된 인증서 생성

구성 파일 `openssl.cnf` 생성:

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
emailAddress              = jjj@email.com

[sans_list]
DNS.1                     = *.test01.com
DNS.2                     = test01.com
DNS.3                     = test.test01.com
EOF
```

키 및 인증서 생성:

```bash
# 개인 키 생성
openssl genrsa -out key.pem 2048

# CSR 생성
openssl req -new -key key.pem \
    -out csr.pem \
    -config openssl.cnf

# 인증서 서명
openssl x509 -req \
    -signkey key.pem \
    -in csr.pem \
    -out cert.pem \
    -extfile openssl.cnf \
    -extensions extension_requirements \
    -days 3650
```

### 2. Google Cloud Certificate Manager 구성

인증서를 업로드하고 맵 엔트리 생성:

```bash
# 인증서 리소스 생성
gcloud certificate-manager certificates create test01-com-cert \
    --certificate-file="cert.pem" \
    --private-key-file="key.pem"

# Certificate Map 생성
gcloud certificate-manager maps create test01-com-map

# 맵 엔트리 생성
gcloud certificate-manager maps entries create test01-com-map-entry \
    --map=test01-com-map \
    --hostname=*.test01.com \
    --certificates=test01-com-cert
```

## 프로젝트 구조

```
.
├── Dockerfile                  # Go 앱 빌드 지침
├── go.mod                      # Go 모듈 정의
├── main.go                     # 애플리케이션 소스 코드
└── manifests/                  # Kubernetes 구성 파일
    ├── deployment.yaml         # 앱 디플로이먼트
    ├── service.yaml            # 앱 서비스 (ClusterIP)
    ├── gateway.yaml            # Gateway 정의 (리스너 및 CertMap 구성)
    ├── gcpgatewaypolicy.yaml   # SSL 정책을 Gateway에 연결
    ├── gcpbackendpolicy.yaml   # Cloud Armor를 서비스에 연결
    ├── healthcheck.yaml        # 커스텀 헬스 체크 구성
    ├── httproute-https.yaml    # HTTPS 라우팅 규칙
    └── httproute-http-redirect.yaml # HTTP -> HTTPS 리다이렉트 규칙
```

## 배포 방법

1.  **컨테이너 이미지 빌드 및 푸시**:
    ```bash
    gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/openfga-sample:v1 .
    ```
    *참고: 이미지 태그를 변경하는 경우 `deployment.yaml`을 업데이트하세요.*

2.  **Kubernetes 매니페스트 적용**:
    ```bash
    kubectl apply -f manifests/
    ```

## 검증

배포를 검증하려면 `curl`을 사용하여 Gateway의 전역 IP 또는 매핑된 호스트 이름을 통해 연결을 테스트할 수 있습니다.

1.  **리소스 확인**:
    ```bash
    kubectl get gateway,httproute,service,gcpbackendpolicy -n test01
    ```

2.  **HTTP 리다이렉트 테스트**:
    ```bash
    # aaa.test01.com을 호스트 이름으로, IP를 전역 IP로 교체하세요
    curl -v http://aaa.test01.com/
    ```
    *예상 출력: `301 Moved Permanently` (HTTPS로 리다이렉트).*

3.  **HTTPS 액세스 테스트**:
    ```bash
    curl -v https://aaa.test01.com/
    ```
    *예상 출력: `200 OK` (본문: `Hello from OpenFGA Sample`).*
