# Mini Project 1 — Secure AWS Web Platform (Terraform)

## 1. Project overview
This project delivers an enterprise-grade, defense-in-depth web infrastructure on Amazon Web Services provisioned entirely as code using HashiCorp Terraform.
The architecture enforces strict network isolation across two Availability Zones, hosting compute and database workloads in private subnets with zero public IP addresses.
Public user traffic is accelerated and secured at the perimeter via an AWS CloudFront distribution configured with HTTPS viewer access and custom origin header verification.
In-depth security controls include tiered security group chaining, stateless Network ACLs, AWS Systems Manager keyless administration, and S3 Block Public Access.
Centralized governance incorporates automated AWS Budgets cost alerts, Secrets Manager credential management, multi-region AWS CloudTrail auditing, and CloudWatch Standard Logging v2 alongside VPC Flow Logs network traffic capture, proactive CloudWatch metric alarms, and a unified operations dashboard backed by Amazon SNS email alerts.

---

## 2. Architecture diagram

```mermaid
flowchart TB
    subgraph Internet["Public Internet"]
        Client["HTTPS Client Browser"]
        Attacker["Direct Internet Attacker"]
    end

    subgraph AWS_Cloud["AWS Cloud (Region: us-east-1)"]
        subgraph Edge_Services["Edge Delivery & Governance"]
            CF["AWS CloudFront Distribution\n(depi-sec-cloudfront)\nEnforces HTTPS | Caching | X-Origin-Verify"]
            Budget["AWS Budgets ($10 USD Alert)\n+ Automated IAM Deny Action"]
            Secrets["AWS Secrets Manager\n(depi-sec-db-credentials)"]
        end

        subgraph VPC["Application VPC: depi-sec-app-vpc (10.0.0.0/16)"]
            IGW["Internet Gateway\n(depi-sec-igw)"]

            subgraph Public_Tier["Public Subnet Tier (Route Table -> IGW)"]
                ALB["Application Load Balancer (depi-sec-alb)\nSecurity Group: depi-sec-alb-sg\nListener: X-Origin-Verify Header Gate\nDefault Action: 403 Forbidden"]
                Subnet_Pub_A["Public Subnet A\n10.0.1.0/24 (us-east-1a)"]
                Subnet_Pub_B["Public Subnet B\n10.0.2.0/24 (us-east-1b)"]
            end

            subgraph Private_Boundary["Stateless Firewall: depi-sec-private-nacl"]
                subgraph Private_Tier["Private Subnet Tier (No Internet Egress)"]
                    Subnet_Priv_A["Private Subnet A: 10.0.11.0/24 (us-east-1a)"]
                    Subnet_Priv_B["Private Subnet B: 10.0.12.0/24 (us-east-1b)"]

                    EC2_A["EC2 App Instance A\n(depi-sec-app-a)\nNo Public IP | Encrypted gp3\nNginx Web Server"]
                    EC2_B["EC2 App Instance B\n(depi-sec-app-b)\nNo Public IP | Encrypted gp3\nNginx Web Server"]

                    EFS["Amazon EFS (depi-sec-efs)\nEncrypted at Rest | Mount: /mnt/shared\nAccess Point: /app-data (UID 1000)"]

                    RDS["Amazon RDS MySQL 8.0 (depi-sec-db)\ndb.t3.micro | 20 GB gp3 | Encrypted\nPublicly Accessible: No"]

                    VPCE["VPC Interface Endpoints\n(ssm, ssmmessages, ec2messages)"]
                end
            end

            S3_GW["VPC Gateway Endpoint: S3\n(com.amazonaws.us-east-1.s3)\nAttached to depi-sec-private-rt"]
        end

        subgraph S3_Buckets["S3 Object Storage (AES-256 / TLS Enforced)"]
            S3_App["App Data Bucket (depi-sec-app-*)\nVersioning + Glacier Lifecycle + PAB"]
            S3_Logs["Central Logs Bucket (depi-sec-logs-*)\nCloudFront Standard Logging v2 + PAB"]
        end
    end

    %% Flow connections
    Client -->|1. HTTPS Request :443| CF
    Attacker -.->|Direct HTTP Request :80| ALB
    ALB -.->|Missing Header -> 403 Forbidden| Attacker

    CF -->|2. HTTP Request with X-Origin-Verify| ALB
    ALB -->|3. Forward to Target Group :80| EC2_A
    ALB -->|3. Forward to Target Group :80| EC2_B

    EC2_A <-->|NFS TCP :2049 via depi-sec-efs-sg| EFS
    EC2_B <-->|NFS TCP :2049 via depi-sec-efs-sg| EFS

    EC2_A -->|MySQL TCP :3306 via depi-sec-db-sg| RDS
    EC2_B -->|MySQL TCP :3306 via depi-sec-db-sg| RDS

    EC2_A -.->|HTTPS :443 via S3 Gateway Endpoint| S3_App
    EC2_B -.->|HTTPS :443 via S3 Gateway Endpoint| S3_App

    EC2_A -.->|HTTPS :443 via PrivateLink| VPCE
    EC2_B -.->|HTTPS :443 via PrivateLink| VPCE

    CF -.->|Standard Access Logs v2| S3_Logs
```

### Architecture Description
The architecture separates public ingress from backend processing and storage across two Availability Zones (`us-east-1a` and `us-east-1b`). Clients access the web application through **AWS CloudFront** over HTTPS, which injects a cryptographic custom header (`X-Origin-Verify`). The **Application Load Balancer (ALB)** in the public subnets checks for this header; direct access to the ALB without the header is blocked with a `403 Forbidden`.

The application tier runs on private Amazon Linux 2023 EC2 instances (`depi-sec-app-a` and `depi-sec-app-b`) with **no public IPs**. Compute instances mount an encrypted **Amazon EFS** shared file system and query a private **Amazon RDS MySQL 8.0** instance. Direct management is handled out-of-band via **AWS Systems Manager Session Manager** through dedicated VPC Interface Endpoints, while S3 storage requests utilize a private **VPC Gateway Endpoint**, ensuring zero exposure to the public internet. Comprehensive auditing and observability are provided by multi-region **AWS CloudTrail** (auditing management actions and S3 data events into a centralized log bucket and CloudWatch Logs), VPC-level **VPC Flow Logs** (`depi-sec-vpc-flow-log`) capturing network IP traffic across every ENI, and proactive **Amazon CloudWatch Alarms** chained to **Amazon SNS** (`depi-sec-alerts`) with a consolidated operational dashboard (**depi-sec-overview**).

---

## 3. Network design table

| VPC / Subnet Name | Resource Identifier | CIDR Block | Availability Zone | Tier Type | Route Table | Routing Target |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`depi-sec-app-vpc`** | `aws_vpc.app_vpc` | `10.0.0.0/16` | Multi-AZ | Parent VPC | N/A | Local routing |
| **`depi-sec-public-a`** | `aws_subnet.public_a` | `10.0.1.0/24` | `us-east-1a` | Public | `depi-sec-public-rt` | `0.0.0.0/0` -> `depi-sec-igw` |
| **`depi-sec-public-b`** | `aws_subnet.public_b` | `10.0.2.0/24` | `us-east-1b` | Public | `depi-sec-public-rt` | `0.0.0.0/0` -> `depi-sec-igw` |
| **`depi-sec-private-a`** | `aws_subnet.private_a` | `10.0.11.0/24` | `us-east-1a` | Private | `depi-sec-private-rt` | `pl-63a5400a` -> `depi-sec-s3-endpoint` |
| **`depi-sec-private-b`** | `aws_subnet.private_b` | `10.0.12.0/24` | `us-east-1b` | Private | `depi-sec-private-rt` | `pl-63a5400a` -> `depi-sec-s3-endpoint` |

> Complete architectural routing explanations and subnet placement rationales are documented in [docs/architecture.md](docs/architecture.md).

---

## 4. Security controls table

| Control ID | Control Name | AWS Service | Threat Mitigated | Evidence Link | Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **SEC-01** | Monthly Budget & Auto-Deny Policy | AWS Budgets / IAM | Unexpected cloud spending; triggers automated IAM deny policy for new expensive instances at 90% spend *(does not hard-cap AWS billing for running resources)* | [02-budget-action.png](screenshots/02-budget/02-budget-action.png) | **Verified (Alerts & Action)** |
| **SEC-02** | Account Password Complexity Policy | AWS IAM | Credential stuffing, weak console passwords | Code verified in `iam.tf` | **Verified** |
| **SEC-03** | Scoped IAM Role for EC2 Instances | AWS IAM | Lateral movement, credential theft from compute | [03-iam-role-trust.png](screenshots/03-iam/03-iam-role-trust.png) | **Verified** |
| **SEC-04** | Private Subnets with No Public IPs | Amazon VPC | Remote port scanning, brute-force internet attacks | [04-vpc-resource-map.png](screenshots/04-vpc/04-vpc-resource-map.png) | **Verified** |
| **SEC-05** | Tiered Security Groups (SG-as-Source) | Amazon EC2 / VPC | Lateral network pivoting, bypass of load balancer | [05-alb-sg-public-http.png](screenshots/05-security/05-alb-sg-public-http.png) | **Verified** |
| **SEC-06** | Stateless Subnet Boundary NACL | Amazon VPC | Protocol tampering, explicit SSH blocking (Port 22) | [06-nacl-inbound-rules.png](screenshots/06-nacl/06-nacl-inbound-rules.png) | **Verified** |
| **SEC-07** | Private VPC Endpoints (S3 & SSM) | AWS PrivateLink | Data exfiltration over public internet, NAT dependency | [07-endpoints-available.png](screenshots/07-endpoint/07-endpoints-available.png) | **Verified** |
| **SEC-08** | Keyless Management via Session Manager | AWS Systems Manager | Stolen SSH private keys, compromised bastion servers *(no public IPs; active SSH attempt not executed)* | [08-session-manager-app-a.png](screenshots/08-session-manager/08-session-manager-app-a.png) | **Verified (Config & Session)** |
| **SEC-09** | Encrypted Persistent Storage (EBS & EFS) | Amazon EBS / EFS | Physical volume theft, unencrypted data at rest | [09-ebs-encrypted-gp3.png](screenshots/09-efs/09-ebs-encrypted-gp3.png) | **Verified** |
| **SEC-10** | S3 Block Public Access & TLS Policy | Amazon S3 | Unintentional data exposure; unauthenticated anonymous read returned HTTP 403 *(explicit ACL mutation not executed)* | [10-s3-public-access-refused.png](screenshots/10-s3/10-s3-public-access-refused.png) | **Verified (Anonymous Refusal)** |
| **SEC-11** | Private RDS MySQL with Secrets Manager | Amazon RDS / Secrets | Direct external database access; internal TCP port 3306 connectivity verified via bash probe *(MySQL auth/queries not tested)* | [11-rds-internal-connection.png](screenshots/11-rds/11-rds-internal-connection.png) | **Verified (Network Reachability)** |
| **SEC-12** | ALB Target Health Checks & Failover | AWS Elastic Load Balancing | Service disruption from compute failure; detected unhealthy target and routed requests to healthy target *(recovered upon restart)* | [12-alb-failover-working.png](screenshots/12-alb/12-alb-failover-working.png) | **Verified** |
| **SEC-13** | CloudFront HTTPS & Origin Verification | AWS CloudFront / ALB | Cleartext eavesdropping; browser HTTPS access verified; direct ALB access returns 403 Forbidden | [13-cloudfront-alb-denied.png](screenshots/13-cloudfront/13-cloudfront-alb-denied.png) | **Verified** |
| **SEC-14** | Multi-Region Audit Logging (CloudTrail) | AWS CloudTrail | Undetected API modifications, administrative credential misuse, unauthorized security group or IAM changes | [14-cloudtrail-settings.png](screenshots/14-cloudtrail/14-cloudtrail-settings.png) | **Verified** |
| **SEC-15** | VPC Flow Logs Network Traffic Auditing | Amazon VPC / CloudWatch Logs | Undetected lateral network movement, unauthorized port scanning, data exfiltration, covert channel communication | [15-flowlog-reject-record.png](screenshots/15-flowlogs/15-flowlog-reject-record.png) | **Verified** |
| **SEC-16** | CloudWatch Metric Alarms & Dashboard | Amazon CloudWatch / SNS | Delayed incident awareness for failing targets, resource starvation, or brute-force console login attempts | [16-dashboard-overview.png](screenshots/16-cloudwatch/16-dashboard-overview.png) | **Verified** |

> Comprehensive threat model analyses and controls descriptions are available in [docs/security-controls.md](docs/security-controls.md).

---

## 5. Prerequisites

Before deploying the platform, ensure the following tooling and configurations are in place:

1. **HashiCorp Terraform:** Version `>= 1.6` installed locally.
   ```bash
   terraform -version
   ```
2. **AWS Command Line Interface (CLI):** Version 2 installed and configured.
   ```bash
   aws --version
   ```
3. **AWS IAM Credentials:** An IAM user or role with administrative access to manage VPC, EC2, IAM, S3, RDS, EFS, CloudFront, Budgets, and Secrets Manager resources.
4. **Target Region:** Deployed in `us-east-1` (North Virginia).
5. **Target Profile:** Set your CLI environment to use your target profile:
   ```bash
   export AWS_PROFILE=depi-terraform
   # or on Windows PowerShell:
   $env:AWS_PROFILE = "depi-terraform"
   ```

---

## 6. How to deploy

Follow these steps to deploy the infrastructure cleanly from scratch:

### Step 1: Clone the Repository
```bash
git clone https://github.com/abouelyazeada-ux/depi-aws-security-mini-project-1.git
cd depi-aws-security-mini-project-1/terraform
```

### Step 2: Initialize Terraform
Initialize the working directory to download the required AWS (`~> 5.0`) and Random (`~> 3.0`) providers:
```bash
terraform init
```

### Step 3: Configure Variables
Create a `terraform.tfvars` file (this file is excluded by `.gitignore` to prevent credential leaks) and specify the alert notification email:
```hcl
alert_email = "your-email@example.com"
region      = "us-east-1"
```

### Step 4: Validate and Plan
Review the proposed execution plan to verify that all resources will be created as intended:
```bash
terraform validate
terraform plan -out=tfplan
```

### Step 5: Apply Infrastructure
Provision the infrastructure:
```bash
terraform apply tfplan
```
*Note: Provisioning the multi-AZ RDS database instance and CloudFront distribution typically takes 8–12 minutes.*

### Step 6: Review Outputs
Terraform will display the provisioned endpoints upon successful completion:
- `cloudfront_domain_name`: The public HTTPS entry point.
- `alb_dns_name`: The origin load balancer DNS.
- `rds_endpoint`: Private MySQL hostname.
- `db_secret_arn`: Secrets Manager ARN storing database credentials.

---

## 7. How to verify

Verification follows the standardized 10-test protocol defined in Task 20. Completed tests (Tasks 1–16) have been empirically verified and are documented below strictly based on observed evidence. Pending tests requiring Tasks 17–20 are designated accordingly.

| # | Test Action | Expected Result | Verified Result | Status | Screenshot Link |
| :-: | :--- | :--- | :--- | :-: | :--- |
| **1** | Open ALB DNS name directly in browser / CLI | HTTP `403 Forbidden` | `curl.exe` returned `403`; browser rendered `"Access Denied"` | **PASS** | [13-cloudfront-alb-denied.png](screenshots/13-cloudfront/13-cloudfront-alb-denied.png) |
| **2** | Open CloudFront distribution URL | Page loads over HTTPS | Loaded `https://dfj4o8x4memfi.cloudfront.net` displaying backend page | **PASS** | [13-cloudfront-https-working.png](screenshots/13-cloudfront/13-cloudfront-https-working.png) |
| **3** | Direct SSH to private EC2 instance IP | Unreachable / Timeout; REJECT record in Flow Logs | Verified instances have no public IPs (`-`); internal TCP port 22 probe from `10.0.11.161` to `10.0.12.241` timed out with exit code 124; CloudWatch Logs Insights confirmed 4 corresponding `REJECT` records on destination TCP port 22; validates TCP network isolation without definitive rule attribution (interactive SSH authentication not tested) | **PASS (Network Isolation & Flow Log REJECT Verified)** | [15-flowlog-reject-record.png](screenshots/15-flowlogs/15-flowlog-reject-record.png) |
| **4** | Connect to RDS from external network | Connection timeout | PowerShell `Test-NetConnection` failed (`TcpTestSucceeded : False`); `Publicly accessible: No` | **PASS** | [11-rds-external-connection-failed.png](screenshots/11-rds/11-rds-external-connection-failed.png) |
| **5** | Connect to RDS from app server via SSM | Port 3306 reachable | Bash `/dev/tcp` probe confirmed: `SUCCESS: RDS port 3306 is reachable` *(MySQL auth/queries not tested)* | **PASS (Network Reachability)** | [11-rds-internal-connection.png](screenshots/11-rds/11-rds-internal-connection.png) |
| **6** | Make S3 object public in bucket | Rejected by Block Public Access | Unauthenticated `curl.exe -I` returned `HTTP/1.1 403 Forbidden`; explicit public ACL mutation **not executed** | **PASS (Anonymous Read Refusal) / PARTIAL** | [10-s3-public-access-refused.png](screenshots/10-s3/10-s3-public-access-refused.png) |
| **7** | Add SSH rule to App SG (Auto-remediation) | Removed by Lambda in <60s | *Pending Task 17 implementation* | **PENDING** | *Awaiting Task 17* |
| **8** | Stop Nginx on one application instance | ALB marks Unhealthy; site up; alarm fires | Target group registered `app-a` Unhealthy; traffic served by `app-b`; CloudWatch alarm `depi-sec-alb-unhealthy-hosts` transitioned to `ALARM`; real SNS alert email received; `depi-sec-overview` dashboard captured spike to 1 and recovery to 0; recovered to Healthy | **PASS** | [12-alb-unhealthy-target.png](screenshots/12-alb/12-alb-unhealthy-target.png)<br>[16-alarm-unhealthy-hosts.png](screenshots/16-cloudwatch/16-alarm-unhealthy-hosts.png)<br>[16-alarm-email-notification.png](screenshots/16-cloudwatch/16-alarm-email-notification.png) |
| **9** | Curl app server from peering tools VPC | HTTP 200 across peering link | *Pending Task 18 implementation* | **PENDING** | *Awaiting Task 18* |
| **10** | Delete recovery point in locked vault | Blocked by Vault Lock policy | *Pending Task 19 implementation* | **PENDING** | *Awaiting Task 19* |

> For comprehensive step-by-step procedures and testing logs, consult [docs/testing.md](docs/testing.md).

---

## 8. Screenshots

All screenshot evidence is organized into dedicated task directories adhering to project naming standards:

### Task 2 — AWS Budget & Cost Anomaly Detection
- **Budget Action Configuration:** Shows the automated $10 budget threshold and IAM deny policy attachment at 90% spend.<br>
  ![Budget Action](screenshots/02-budget/02-budget-action.png)
- **Budget Overview Dashboard:** Demonstrates the active monthly cost tracking and forecast.<br>
  ![Budget Overview](screenshots/02-budget/02-budget-overview.png)

### Task 3 — IAM Least Privilege Configuration
- **EC2 Trust Relationship:** Confirms the instance role can only be assumed by `ec2.amazonaws.com`.<br>
  ![IAM Role Trust](screenshots/03-iam/03-iam-role-trust.png)
- **Scoped S3 Policy:** Demonstrates the inline policy restricting `s3:GetObject` strictly to the application bucket.<br>
  ![IAM S3 Policy JSON](screenshots/03-iam/03-iam-s3-policy-json.png)

### Task 4 — Multi-AZ VPC Architecture
- **VPC Resource Map:** Visualizes the dual-AZ subnet topology across public and private tiers.<br>
  ![VPC Resource Map](screenshots/04-vpc/04-vpc-resource-map.png)
- **Public Route Table:** Confirms routing for `0.0.0.0/0` targeting the Internet Gateway (`depi-sec-igw`).<br>
  ![Public Route Table](screenshots/04-vpc/04-public-route-table.png)
- **Private Route Table:** Demonstrates isolated private routing with no internet gateway route.<br>
  ![Private Route Table](screenshots/04-vpc/04-private-route-table.png)

### Task 5 — Tiered Security Groups
- **ALB Security Group:** Permits public HTTP traffic on port 80.<br>
  ![ALB SG](screenshots/05-security/05-alb-sg-public-http.png)
- **App Security Group:** Enforces ingress on port 80 referencing `depi-sec-alb-sg` as source.<br>
  ![App SG](screenshots/05-security/05-app-sg-source.png)
- **Database Security Group:** Restricts port 3306 ingress strictly to `depi-sec-app-sg`.<br>
  ![DB SG](screenshots/05-security/05-db-sg-source.png)
- **EFS Security Group:** Restricts NFS port 2049 ingress strictly to `depi-sec-app-sg`.<br>
  ![EFS SG](screenshots/05-security/05-efs-sg-source.png)

### Task 6 — Network Access Control Lists (NACLs)
- **Inbound NACL Rules:** Demonstrates stateless rule ordering and Rule 200 explicitly denying port 22.<br>
  ![NACL Inbound Rules](screenshots/06-nacl/06-nacl-inbound-rules.png)
- **Outbound NACL Rules:** Shows permitted outbound response rules.<br>
  ![NACL Outbound Rules](screenshots/06-nacl/06-nacl-outbound-rules.png)
- **Subnet Associations:** Confirms association with `depi-sec-private-a` and `depi-sec-private-b`.<br>
  ![NACL Subnet Associations](screenshots/06-nacl/06-nacl-subnet-associations.png)

### Task 7 — Private VPC Endpoints
- **VPC Endpoints Available:** Shows active Status `Available` for S3 Gateway and SSM Interface endpoints.<br>
  ![VPC Endpoints Available](screenshots/07-endpoint/07-endpoints-available.png)
- **S3 Route Table Entry (CLI):** Verifies the AWS S3 prefix list route inside the private route table via AWS CLI.<br>
  ![S3 Route CLI](screenshots/07-endpoint/07-s3-gateway-route-cli.png)
- **S3 Route Table Entry (Console):** Verifies the S3 Gateway endpoint target in the AWS Console.<br>
  ![S3 Route Console](screenshots/07-endpoint/07-s3-gateway-route-console.png)

### Task 8 — EC2 Instances & Keyless Session Manager Access
- **Instance A — Zero Public IP:** Confirms `depi-sec-app-a` has no public IPv4 address (`-`).<br>
  ![Instance A No Public IP](screenshots/08-session-manager/08-ec2-app-a-no-public-ip.png)
- **Instance B — Zero Public IP:** Confirms `depi-sec-app-b` has no public IPv4 address (`-`).<br>
  ![Instance B No Public IP](screenshots/08-session-manager/08-ec2-app-b-no-public-ip.png)
- **Session Manager Terminal (App A):** Proves remote interactive shell access without SSH keys or port 22.<br>
  ![Session Manager App A](screenshots/08-session-manager/08-session-manager-app-a.png)
- **Session Manager Terminal (App B):** Proves remote interactive shell access to instance B.<br>
  ![Session Manager App B](screenshots/08-session-manager/08-session-manager-app-b.png)

### Task 9 — Encrypted Shared Storage (EBS & EFS)
- **Encrypted EBS gp3 Volume:** Confirms root volume encryption at rest using AWS managed keys.<br>
  ![Encrypted EBS](screenshots/09-efs/09-ebs-encrypted-gp3.png)
- **EFS Mount Targets:** Confirms multi-AZ mount targets inside both private subnets.<br>
  ![EFS Mount Targets](screenshots/09-efs/09-efs-mount-targets.png)
- **Shared File Verification:** Demonstrates reading and writing to `/mnt/shared` simultaneously across instances.<br>
  ![Shared File Proof](screenshots/09-efs/09-efs-shared-file.png)

### Task 10 — S3 Buckets & Data Protection
- **App Bucket Public Access Block:** Shows all 4 Block Public Access settings enabled on application bucket.<br>
  ![App Bucket PAB](screenshots/10-s3/10-app-bucket-public-access-block.png)
- **App Bucket Versioning & Encryption:** Demonstrates active Versioning and AES256 default encryption.<br>
  ![App Bucket Versioning](screenshots/10-s3/10-app-bucket-versioning-encryption.png)
- **App Bucket Lifecycle Rules:** Shows non-current version transition to Glacier and expiration rules.<br>
  ![App Bucket Lifecycle](screenshots/10-s3/10-app-bucket-lifecycle.png)
- **Logs Bucket Public Access Block:** Confirms Block Public Access on centralized logging bucket.<br>
  ![Logs Bucket PAB](screenshots/10-s3/10-logs-bucket-public-access-block.png)
- **Logs Bucket Versioning & Encryption:** Shows Versioning and AES256 default encryption.<br>
  ![Logs Bucket Versioning](screenshots/10-s3/10-logs-bucket-versioning-encryption.png)
- **Logs Bucket Lifecycle Rules:** Confirms automated object lifecycle management.<br>
  ![Logs Bucket Lifecycle](screenshots/10-s3/10-logs-bucket-lifecycle.png)
- **Refused Public Access Test:** Demonstrates unauthenticated `curl.exe -I` request to test object returning `HTTP/1.1 403 Forbidden`.<br>
  ![Refused Public Access](screenshots/10-s3/10-s3-public-access-refused.png)

### Task 11 — Private RDS MySQL Database
- **Storage Encryption:** Confirms RDS volume encryption at rest with KMS.<br>
  ![RDS Encryption](screenshots/11-rds/11-rds-encryption.png)
- **Private Subnet Accessibility:** Proves `Publicly accessible` is set to `No`.<br>
  ![RDS Private Access](screenshots/11-rds/11-rds-private-access.png)
- **Internal Database Reachability:** Shows bash `/dev/tcp` socket probe confirming TCP port 3306 is reachable from `depi-sec-app-a`.<br>
  ![RDS Internal Query](screenshots/11-rds/11-rds-internal-connection.png)
- **External Connection Failure:** Shows PowerShell `Test-NetConnection` failing to reach port 3306 from an external client (`TcpTestSucceeded : False`).<br>
  ![RDS External Timeout](screenshots/11-rds/11-rds-external-connection-failed.png)

### Task 12 — Application Load Balancer
- **Healthy Target Group:** Shows both EC2 instances passing health checks.<br>
  ![Healthy Targets](screenshots/12-alb/12-alb-healthy-targets.png)
- **Target Failure Simulation:** Shows `depi-sec-app-a` marked `Unhealthy` after stopping Nginx.<br>
  ![Unhealthy Target](screenshots/12-alb/12-alb-unhealthy-target.png)
- **Continuous Availability:** Shows client traffic serving from `depi-sec-app-b` while target `app-a` was unhealthy.<br>
  ![Failover Working](screenshots/12-alb/12-alb-failover-working.png)
- **Automated Target Recovery:** Shows target group returning to fully healthy status upon service restart.<br>
  ![Targets Recovered](screenshots/12-alb/12-alb-recovered.png)
- **Application Page Rendering:** Displays successful rendering of instance host details.<br>
  ![Working Web Page](screenshots/12-alb/12-alb-working-page.png)
- **Instance B Web Serving:** Shows response load balanced to instance B.<br>
  ![App B Page](screenshots/12-alb/12-alb-app-b.png)

### Task 13 — CloudFront HTTPS & Origin Protection
- **HTTPS Enforcement:** Displays CloudFront distribution serving over HTTPS via distribution domain.<br>
  ![CloudFront HTTPS](screenshots/13-cloudfront/13-cloudfront-https-working.png)
- **Direct ALB Access Denied:** Proves direct access to ALB DNS name returns `403 Forbidden`.<br>
  ![ALB Denied](screenshots/13-cloudfront/13-cloudfront-alb-denied.png)
- **403 Status Code Inspection:** Displays `curl.exe` output showing HTTP status code `403`.<br>
  ![403 Status](screenshots/13-cloudfront/13-cloudfront-403-status.png)
- **Standard Logging v2 Delivery:** Demonstrates CloudWatch access logs delivering to S3 logs bucket.<br>
  ![CloudFront Logging](screenshots/13-cloudfront/13-cloudfront-logging.png)

### Task 14 — AWS CloudTrail & Governance Logging
- **CloudTrail Configuration & Delivery Settings:** Confirms multi-region logging active for `depi-sec-trail`, log file validation enabled, and delivery to centralized S3 logs bucket (`depi-sec-logs-*`) and CloudWatch Log Group `/aws/cloudtrail/depi-sec-trail` with 14-day retention.<br>
  ![CloudTrail Settings](screenshots/14-cloudtrail/14-cloudtrail-settings.png)
- **CloudTrail Management Event & Identity Record:** Displays recorded management event (`StartLogging`) verifying user identity (`terraform-admin`), IAM user ARN, access key ID, source IP address (`156.217.85.8`), and event details.<br>
  ![CloudTrail Event Identity](screenshots/14-cloudtrail/14-cloudtrail-event-identity.png)

### Task 15 — VPC Flow Logs & Network Traffic Auditing
- **CloudWatch Logs Insights Port 22 REJECT Record:** Demonstrates VPC Flow Logs capturing IP traffic across `depi-sec-app-vpc` to log group `/depi-sec/vpc/flowlogs`. A CloudWatch Logs Insights query explicitly scoped to log group `/depi-sec/vpc/flowlogs` (filtering on `dstport = "22" and action = "REJECT"`) returned four matching records, including an internal TCP port 22 connection attempt from `depi-sec-app-a` (`10.0.11.161`) to `depi-sec-app-b` (`10.0.12.241`) that timed out with exit code 124, verifying Layer 4 network isolation without definitive rule attribution (interactive SSH authentication not tested).<br>
  ![VPC Flow Log REJECT Record](screenshots/15-flowlogs/15-flowlog-reject-record.png)

#### Explanation of the 14 Default VPC Flow Log Fields
AWS VPC Flow Logs capture network IP traffic metadata using 14 standard space-delimited fields. The verified REJECT record observed in CloudWatch Logs Insights is:
```text
2 882034443616 eni-0b401abe98593901c 10.0.11.161 10.0.12.241 58932 22 6 3 180 1792100814 1792100825 REJECT OK
```

| Field # | Field Name | Description | Verified Record Value |
| :-: | :--- | :--- | :--- |
| **1** | `version` | The VPC Flow Log version format. Version `2` corresponds to the standard default AWS format. | `2` |
| **2** | `account-id` | The 12-digit AWS account ID of the resource owner. | `882034443616` |
| **3** | `interface-id` | The Elastic Network Interface (ENI) identifier on which the traffic was recorded. | `eni-0b401abe98593901c` |
| **4** | `srcaddr` | The source IPv4 address of the originating network entity. | `10.0.11.161` (`depi-sec-app-a`) |
| **5** | `dstaddr` | The destination IPv4 address targeted by the network connection. | `10.0.12.241` (`depi-sec-app-b`) |
| **6** | `srcport` | The source port number chosen by the sending host. | `58932` |
| **7** | `dstport` | The destination port number targeted by the traffic (e.g., port 22 for SSH). | `22` |
| **8** | `protocol` | The IANA standard protocol number (e.g., `6` for TCP, `17` for UDP, `1` for ICMP). | `6` (TCP) |
| **9** | `packets` | The total number of packets transferred during the capture aggregation window. | `3` |
| **10** | `bytes` | The cumulative count of bytes transferred during the capture aggregation window. | `180` |
| **11** | `start` | The Unix timestamp (in epoch seconds) marking the beginning of the aggregation interval. | `1792100814` |
| **12** | `end` | The Unix timestamp (in epoch seconds) marking the end of the aggregation interval. | `1792100825` |
| **13** | `action` | The security decision applied to the traffic: `ACCEPT` (permitted by both SG and NACL) or `REJECT` (blocked by SG or NACL). | `REJECT` |
| **14** | `log-status` | The operational status of the logging service: `OK` (logged normally), `NODATA` (no traffic during interval), or `SKIPDATA` (records skipped due to internal capacity constraints). | `OK` |

### Task 16 — CloudWatch Alarms & Operations Dashboard
- **Operations Dashboard (`depi-sec-overview`):** Demonstrates the real-time CloudWatch operational dashboard tracking all four key metrics: EC2 CPU utilization across both application servers, ALB unhealthy host count (capturing the test spike to 1 and recovery to 0), RDS MySQL available storage space, and CloudTrail failed console logins.<br>
  ![Dashboard Overview](screenshots/16-cloudwatch/16-dashboard-overview.png)
- **ALB Unhealthy Target Alarm Triggered:** Demonstrates CloudWatch Alarm `depi-sec-alb-unhealthy-hosts` entering `In alarm` state when Nginx was stopped on `depi-sec-app-a`, showing active monitoring and evaluation.<br>
  ![Alarm State](screenshots/16-cloudwatch/16-alarm-unhealthy-hosts.png)
- **Real SNS Alert Email Delivery:** Shows the actual email notification received from Amazon SNS (`depi-sec-alerts`) delivering the alarm payload with state transition (`OK -> ALARM`), affected resource ARNs, and threshold details.<br>
  ![Alarm Email Notification](screenshots/16-cloudwatch/16-alarm-email-notification.png)

---

## 9. Cost notes

### Resource Cost Breakdown
Building secure cloud platforms requires understanding which services incur hourly or usage-based charges:

| Service / Resource | Pricing Model | Estimated Cost Impact | Optimization Applied |
| :--- | :--- | :--- | :--- |
| **AWS Application Load Balancer** | ~$0.0225/hour + LCU charges | ~$16.20 / month | Single ALB deployed across 2 public subnets |
| **VPC Interface Endpoints (3x)** | ~$0.01/hour per AZ per endpoint | ~$21.60 / month | Scoped strictly to required SSM services (`ssm`, `ssmmessages`, `ec2messages`) |
| **VPC Gateway Endpoint (S3)** | **Free** ($0.00) | $0.00 | Uses Gateway endpoint to route S3 traffic without NAT costs |
| **NAT Gateways** | ~$0.045/hour + data processing | **$0.00 (Avoided)** | Architected with **Zero NAT Gateways**; all AWS communication utilizes endpoints |
| **Amazon RDS MySQL (db.t3.micro)** | AWS Free Tier eligible (750 hrs) | $0.00 / month | Sized at `db.t3.micro` with single-AZ deployment for educational scope |
| **Amazon EC2 (2x t3.micro)** | AWS Free Tier eligible (750 hrs) | $0.00 / month | Uses Amazon Linux 2023 `t3.micro` instances |
| **AWS Secrets Manager** | $0.40/secret/month | ~$0.40 / month | Single secret storing database master credentials |
| **AWS CloudFront** | 1 TB free transfer per month | $0.00 / month | `PriceClass_100` (North America and Europe) |
| **Amazon EFS** | 5 GB free storage per month | $0.00 / month | Lightweight access point with TLS encryption |
| **AWS CloudTrail** | Free tier for 1st management copy | ~$0.00 / month | Multi-region trail with S3 read data events scoped to app bucket |
| **Amazon CloudWatch Logs (VPC Flow Logs)** | $0.50/GB ingested + $0.03/GB/mo storage | ~$0.25 / month | Aggregates VPC-level network traffic with 14-day retention |
| **Amazon CloudWatch (Alarms & Dashboard)** | $0.10/alarm/month + free dashboard tier | ~$0.50 / month | 5 standard-resolution alarms with dashboard utilizing free tier allocation |
| **Amazon Simple Notification Service (SNS)** | Free tier for 1st 1,000 email alerts | $0.00 / month | Scoped email subscription for administrator alerts without KMS CMK costs |

### Cost Guardrail Safeguards & Budget Boundaries
- An active monthly budget (`depi-sec-monthly`) of **$10.00 USD** is enforced.
- Automated email alerts fire at **80% actual spend ($8.00)** and **100% forecasted spend ($10.00)**.
- At **90% actual spend ($9.00)**, an automated IAM Budget Action attaches `depi-sec-deny-expensive` to developer groups, immediately blocking any creation of new EC2 or RDS instances.
- **Critical Cost Distinction (Alerts vs Hard Spending Limits):** A $10 budget in AWS is a tracking and alerting tool, not a hard spending cap. AWS Budgets does not shut down or terminate running resources when the threshold is reached. Running EC2 instances, Application Load Balancers, RDS instances, and VPC Interface Endpoints continue to accrue hourly charges regardless of budget alerts until explicitly stopped or destroyed using `terraform destroy`.

---

## 10. How to destroy

To prevent unexpected billing after completing project evaluations, destroy all deployed infrastructure cleanly:

### Step 1: Empty S3 Buckets
Amazon S3 blocks bucket deletion if objects, non-current versions, or delete markers remain. Empty both buckets prior to running Terraform:
```bash
# Retrieve bucket names from Terraform state
APP_BUCKET=$(terraform output -raw app_bucket_name 2>/dev/null || aws s3 ls | grep depi-sec-app | awk '{print $3}')
LOGS_BUCKET=$(terraform output -raw logs_bucket_name 2>/dev/null || aws s3 ls | grep depi-sec-logs | awk '{print $3}')

# Empty all versions and delete markers
aws s3api delete-objects --bucket "$APP_BUCKET" \
  --delete "$(aws s3api list-object-versions --bucket "$APP_BUCKET" --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
aws s3api delete-objects --bucket "$LOGS_BUCKET" \
  --delete "$(aws s3api list-object-versions --bucket "$LOGS_BUCKET" --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
```

### Step 2: Run Terraform Destroy
Execute Terraform destroy from the `terraform/` directory:
```bash
terraform destroy
```
Review the proposed destruction plan (confirming removal of CloudFront, ALB, RDS, EC2, VPC Endpoints, and IAM roles) and type `yes`.

### Step 3: Verify Clean Console
Open the AWS Management Console in `us-east-1` and verify that the following dashboards are completely clear:
- **EC2 Console:** 0 running instances, 0 load balancers, 0 target groups.
- **RDS Console:** 0 DB instances.
- **VPC Console:** 0 endpoints, 0 custom VPCs.
- **CloudFront Console:** 0 distributions.

*(Note for Task 19: When AWS Backup Vault Lock is implemented with a compliance retention window, locked recovery points cannot be deleted until the retention period expires. In such a scenario, destroy all remaining infrastructure and document the expiration timestamp).*

---

## 11. What I learned

1. **Defense-in-depth is significantly more resilient than perimeter security.** Implementing multiple decoupled layers (CloudFront header gating, ALB listener rules, Security Group chaining, stateless NACLs, and OS-level firewalls) ensures that if an attacker bypasses one layer, the system does not fail catastrophically.
2. **Security Group Referencing (SG-as-Source) completely outclasses CIDR-based firewalling.** Referencing security group IDs eliminates hardcoded IP addresses, remains robust during auto-scaling or instance replacement, and guarantees that backend tiers only receive traffic from approved upstream tiers.
3. **Stateless Network ACLs require explicit ephemeral port planning.** Because NACLs are stateless, allowing inbound traffic on port 80/443 without opening outbound ephemeral ports (1024–65535) results in silent connection drops. Understanding TCP handshake mechanics is essential for configuring NACLs correctly.
4. **Bastionless management via AWS Systems Manager Session Manager is vastly superior to SSH.** Eliminating SSH private keys, disabling port 22, and provisioning EC2 instances without public IPs dramatically shrinks the attack surface while generating centralized, non-repudiable audit logs.
5. **Private VPC Endpoints eliminate the necessity of expensive NAT Gateways.** Leveraging Gateway Endpoints for S3 and Interface Endpoints (PrivateLink) for Systems Manager allows compute instances in private subnets to interact with AWS services entirely on private AWS fiber, achieving high security while reducing egress and NAT hourly charges.
6. **Edge termination is not identical to end-to-end encryption.** While browser HTTPS access was verified at CloudFront, forwarding over HTTP to an ALB origin creates a cleartext vulnerability across public transit networks, emphasizing the necessity of custom ACM certificates on backend load balancers in production.
7. **S3 Block Public Access is a critical safety net against human error.** Enforcing all four S3 Block Public Access flags at the account and bucket level prevents accidental public data exposure even if an engineer attempts to apply a public ACL.
8. **Automated cost controls must include proactive policy enforcement.** Relying solely on email alerts during a compromise or accidental deployment is insufficient; configuring automated IAM actions that attach deny policies at budget thresholds prevents creating expensive new resources, though running resources must still be managed.
9. **Terraform lifecycle blocks and dependency ordering are vital for zero-downtime operations.** Utilizing `lifecycle { ignore_changes = [ami] }` prevents unexpected instance replacements when AWS publishes updated base AMIs, and explicit `depends_on` clauses ensure storage mount targets exist before compute instances attempt mounts.
10. **Negative testing is as critical as positive functional testing.** Validating that unauthorized actions fail (e.g., verifying 403 Forbidden on direct ALB access, TCP connection failures on RDS from external networks, and refused public S3 reads) provides empirical proof that security controls are genuinely active without assuming unexecuted application layers.
11. **Comprehensive network visibility requires passive flow auditing at the VPC root boundary.** Provisioning VPC Flow Logs at the VPC level provides unified visibility into every Elastic Network Interface without requiring in-guest agents and operating independently of guest operating system and application workloads. Analyzing the 14 default fields enables engineers to distinguish normal traffic (`ACCEPT`) from scanning activity or unauthorized lateral movement (`REJECT`) across both public and private subnets.
12. **Audit trails require multi-layered log shipping to prevent tampering.** Streaming CloudTrail management and data events simultaneously to encrypted Amazon S3 (for long-term tamper-evident archival with log file validation) and Amazon CloudWatch Logs (for real-time metric filtering and rapid querying via CloudWatch Logs Insights) combines immutability with incident response agility.
13. **Proactive observability and alerting must separate infrastructure metrics from security signals.** While operational alarms (ALB target health, EC2 CPU, RDS storage) track resource availability and performance, security alarms (CloudTrail metric filters for failed console authentication) deliver automated incident awareness. Chaining CloudWatch alarms to Amazon SNS with least-privilege topic policies enables rapid, automated operator notification without introducing fragile third-party dependencies or KMS key overhead.

---

## 12. Known limitations

While the platform implements rigorous security controls for completed Tasks 1–16, several known architectural limitations exist that should be addressed in a production deployment:

1. **Unencrypted HTTP Between CloudFront and Application Load Balancer:**
   - *Limitation:* The CloudFront origin protocol policy is set to `http-only` on port 80 as mandated by the educational project scope.
   - *Risk:* Traffic between AWS CloudFront edge servers and the ALB origin travels over plain HTTP across public network paths.
   - *Production Solution:* Issue a validated public TLS certificate using AWS Certificate Manager (ACM), bind an HTTPS listener on port 443 with TLS 1.3 to the ALB, and configure CloudFront origin protocol policy to `https-only`.
2. **Custom Header Origin Verification is Not a True Network Perimeter:**
   - *Limitation:* The ALB listener rule verifies the `X-Origin-Verify` static secret header, returning HTTP 403 on direct requests.
   - *Risk:* The ALB remains internet-facing with public IP addresses. Direct attacks still initiate TCP/HTTP handshakes that consume load balancer capacity, leaving the ALB exposed to direct Layer 4/7 DoS attacks. Additionally, if the static header leaks, an attacker can bypass CloudFront.
   - *Production Solution:* Attach **AWS CloudFront Managed Prefix Lists** (`aws_ec2_managed_prefix_list`) directly to the ALB security group inbound rules to drop all non-CloudFront traffic at the network packet layer, and deploy **AWS WAF** with rate limiting and automated secret rotation.
3. **Absence of AWS WAF:**
   - *Limitation:* No Web Application Firewall is currently attached to CloudFront or the ALB.
   - *Production Solution:* Deploy AWS WAF with AWS Managed Rules (Common Rule Set, Known Bad Inputs, SQLi/XSS inspection, and IP reputation lists).
4. **Single-AZ RDS Deployment:**
   - *Limitation:* To minimize lab costs, RDS MySQL is deployed as a single instance (`multi_az = false`).
   - *Production Solution:* Enable `multi_az = true` for automated synchronous standby failover across availability zones.
5. **Cost Monitoring vs Hard Spending Limits:**
   - *Limitation:* AWS Budgets provides alerts and automated IAM deny policies for new resources, but AWS does not natively enforce hard billing caps that automatically terminate running infrastructure.
   - *Production Solution:* Deploy automated EventBridge and Lambda functions to shut down or delete test resources if budget thresholds are breached.
6. **Outstanding Project Tasks (Tasks 17–20):**
   - Automated Lambda security remediation (Task 17), VPC Peering for administrative isolation (Task 18), immutable AWS Backup vault locking (Task 19), and final teardown/cost validation (Task 20) remain to be completed in subsequent implementation phases. Tasks 1–16 are fully deployed, verified, and documented.
