# Security Controls Matrix — Secure AWS Web Platform

This document serves as the primary security compliance audit reference for the platform. It details each security control implemented across **Tasks 1–18**, identifying the governing AWS service, the threat or attack vector mitigated, the implementation mechanism in Terraform, and the verifying screenshot evidence.

Unimplemented controls scheduled for **Tasks 19–20** are clearly designated as **Pending Implementation** at the conclusion of this document.

---

## 1. Security Controls Master Table (Tasks 1–18)

| Control ID | Security Control | AWS Service | Threat Mitigated | Terraform Implementation | Verifying Screenshot | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **SEC-01** | **Automated Cost Guardrails & Resource Deny** | AWS Budgets & IAM | Runaway cloud spend, cryptomining malware, compromised credentials launching expensive instances. | `aws_budgets_budget.monthly` ($10 USD limit, 80% actual, 100% forecasted alerts) + `aws_budgets_budget_action` applying `aws_iam_policy.deny_expensive` (`ec2:RunInstances`, `rds:CreateDBInstance`) at 90% actual spend. *Note: Provides alerts and prevents new expensive resources; does not hard-cap AWS billing for running resources.* | [`02-budget-action.png`](../screenshots/02-budget/02-budget-action.png)<br>[`02-budget-overview.png`](../screenshots/02-budget/02-budget-overview.png) | **Verified (Alerts & Action)** |
| **SEC-02** | **Account Password Hardening Policy** | AWS IAM | Credential stuffing, weak password dictionary attacks on console identities. | `aws_iam_account_password_policy.strict` (min 14 chars, upper/lower/numbers/symbols required, 90-day expiration, password reset required for new users). | *Code verified in `iam.tf`* | **Verified** |
| **SEC-03** | **Least Privilege EC2 Instance Profile** | AWS IAM | Lateral movement and unauthorized data exfiltration if an application server is compromised. | `aws_iam_role.ec2_role` scoped strictly to `AmazonSSMManagedInstanceCore` and customer-managed policy `depi-sec-s3-app-read` granting `s3:GetObject` only to `arn:aws:s3:::depi-sec-app-*/*`. No IAM credentials stored on EC2. | [`03-iam-role-trust.png`](../screenshots/03-iam/03-iam-role-trust.png)<br>[`03-iam-s3-policy-json.png`](../screenshots/03-iam/03-iam-s3-policy-json.png) | **Verified** |
| **SEC-04** | **VPC Network Isolation & Zero Public IPs** | Amazon VPC | Direct internet-based port scanning, reconnaissance, and unauthorized remote access. | Private subnets `depi-sec-private-a` (`10.0.11.0/24`) and `depi-sec-private-b` (`10.0.12.0/24`) configured with `map_public_ip_on_launch = false`. Route table has no route to Internet Gateway. | [`04-vpc-resource-map.png`](../screenshots/04-vpc/04-vpc-resource-map.png)<br>[`04-public-route-table.png`](../screenshots/04-vpc/04-public-route-table.png)<br>[`04-private-route-table.png`](../screenshots/04-vpc/04-private-route-table.png) | **Verified** |
| **SEC-05** | **Tiered Security Group Chaining (SG-as-Source)** | Amazon EC2 / VPC | Lateral network pivoting; bypass of application load balancer; direct access to database or storage. | Strict ingress chaining: `depi-sec-app-sg` permits port 80 only from `depi-sec-alb-sg`; `depi-sec-db-sg` permits port 3306 only from `depi-sec-app-sg`; `depi-sec-efs-sg` permits port 2049 only from `depi-sec-app-sg`. | [`05-alb-sg-public-http.png`](../screenshots/05-security/05-alb-sg-public-http.png)<br>[`05-app-sg-source.png`](../screenshots/05-security/05-app-sg-source.png)<br>[`05-db-sg-source.png`](../screenshots/05-security/05-db-sg-source.png)<br>[`05-efs-sg-source.png`](../screenshots/05-security/05-efs-sg-source.png) | **Verified** |
| **SEC-06** | **Stateless Subnet Boundary Defense (NACL)** | Amazon VPC | Unauthorized protocols, SSH brute-forcing at the network packet boundary. | `depi-sec-private-nacl` attached to private subnets with Rule 200 explicitly denying inbound TCP port 22 from `0.0.0.0/0`, and tightly restricting ingress to VPC CIDR (`10.0.0.0/16`). Rules 150–152 and 150–151 permit inter-VPC traffic from Tools subnet `10.1.1.0/24`. | [`06-nacl-inbound-rules.png`](../screenshots/06-nacl/06-nacl-inbound-rules.png)<br>[`06-nacl-outbound-rules.png`](../screenshots/06-nacl/06-nacl-outbound-rules.png)<br>[`06-nacl-subnet-associations.png`](../screenshots/06-nacl/06-nacl-subnet-associations.png) | **Verified** |
| **SEC-07** | **Private AWS Service Connectivity via VPC Endpoints** | AWS PrivateLink | Data leakage over public internet; dependency on NAT gateways or public internet routes for AWS APIs. | S3 Gateway Endpoint (`com.amazonaws.us-east-1.s3`) on private route table; Interface Endpoints for `ssm`, `ssmmessages`, and `ec2messages` in both private subnets with `depi-sec-endpoint-sg` restricting port 443 to `10.0.0.0/16` and Tools subnet `10.1.1.0/24`. | [`07-endpoints-available.png`](../screenshots/07-endpoint/07-endpoints-available.png)<br>[`07-s3-gateway-route-cli.png`](../screenshots/07-endpoint/07-s3-gateway-route-cli.png)<br>[`07-s3-gateway-route-console.png`](../screenshots/07-endpoint/07-s3-gateway-route-console.png) | **Verified** |
| **SEC-08** | **Bastionless & Keyless Systems Management** | AWS Systems Manager & EC2 | Stolen SSH private keys, compromised bastion hosts, unauthorized interactive shell access. | Zero SSH key pairs generated. Zero open port 22 rules in security groups. EC2 instances managed exclusively via AWS Systems Manager Session Manager using IAM role credentials. Verified instances have no public IPs (`-`). *Note: Active SSH connection attempt was not executed.* | [`08-session-manager-app-a.png`](../screenshots/08-session-manager/08-session-manager-app-a.png)<br>[`08-session-manager-app-b.png`](../screenshots/08-session-manager/08-session-manager-app-b.png)<br>[`08-ec2-app-a-no-public-ip.png`](../screenshots/08-session-manager/08-ec2-app-a-no-public-ip.png)<br>[`08-ec2-app-b-no-public-ip.png`](../screenshots/08-session-manager/08-ec2-app-b-no-public-ip.png) | **Verified (Config & Session)** |
| **SEC-09** | **Cryptographic Storage Protection at Rest** | Amazon EBS & Amazon EFS | Physical disk theft, unauthorized data inspection from raw block/file storage snapshots. | EC2 root volumes use `root_block_device { encrypted = true, volume_type = "gp3" }`. `aws_efs_file_system` configured with `encrypted = true`. EFS Access Point enforces POSIX identity `uid=1000, gid=1000`. | [`09-ebs-encrypted-gp3.png`](../screenshots/09-efs/09-ebs-encrypted-gp3.png)<br>[`09-efs-mount-targets.png`](../screenshots/09-efs/09-efs-mount-targets.png)<br>[`09-efs-shared-file.png`](../screenshots/09-efs/09-efs-shared-file.png) | **Verified** |
| **SEC-10** | **Multi-Layer S3 Object & Data Security** | Amazon S3 | Accidental data leak, public data scraping, data tampering, ransomware, unencrypted transit. | App and Logs buckets enforce: (1) S3 Block Public Access (all 4 flags `true`), (2) Default `AES256` SSE, (3) Object Versioning `Enabled`, (4) Bucket policy denying non-HTTPS traffic (`aws:SecureTransport = false`), (5) 30d Glacier transition and 365d expiration lifecycle rules. Unauthenticated anonymous read of test object returned `HTTP/1.1 403 Forbidden`. *Note: Explicit public ACL mutation was not executed.* | [`10-app-bucket-public-access-block.png`](../screenshots/10-s3/10-app-bucket-public-access-block.png)<br>[`10-app-bucket-versioning-encryption.png`](../screenshots/10-s3/10-app-bucket-versioning-encryption.png)<br>[`10-app-bucket-lifecycle.png`](../screenshots/10-s3/10-app-bucket-lifecycle.png)<br>[`10-logs-bucket-public-access-block.png`](../screenshots/10-s3/10-logs-bucket-public-access-block.png)<br>[`10-logs-bucket-versioning-encryption.png`](../screenshots/10-s3/10-logs-bucket-versioning-encryption.png)<br>[`10-logs-bucket-lifecycle.png`](../screenshots/10-s3/10-logs-bucket-lifecycle.png)<br>[`10-s3-public-access-refused.png`](../screenshots/10-s3/10-s3-public-access-refused.png) | **Verified (Anonymous Refusal)** |
| **SEC-11** | **Private Relational Database Isolation & Secrets Management** | Amazon RDS & Secrets Manager | Database credential leakage in source control; direct internet SQL injection or port 3306 attacks. | RDS MySQL deployed in private DB subnet group; `publicly_accessible = false`; storage encrypted with KMS (`gp3`); master password generated dynamically via `random_password` and stored in AWS Secrets Manager (`depi-sec-db-credentials`). External TCP probe failed (`TcpTestSucceeded : False`); internal bash TCP probe confirmed port 3306 reachable. *Note: MySQL authentication and query execution were not tested.* | [`11-rds-encryption.png`](../screenshots/11-rds/11-rds-encryption.png)<br>[`11-rds-private-access.png`](../screenshots/11-rds/11-rds-private-access.png)<br>[`11-rds-internal-connection.png`](../screenshots/11-rds/11-rds-internal-connection.png)<br>[`11-rds-external-connection-failed.png`](../screenshots/11-rds/11-rds-external-connection-failed.png) | **Verified (Network Reachability)** |
| **SEC-12** | **Application Load Balancing & Target Health Checking** | AWS Elastic Load Balancing | Single point of failure; compute instance failure taking down web services. | Application Load Balancer deployed across public subnets in two AZs; target group checks HTTP `/` every 30s. Target failure detected when web service stopped on `app-a`; traffic served by healthy target `app-b`. Targets recovered to Healthy upon restart (*timing/zero-downtime claims omitted*). | [`12-alb-healthy-targets.png`](../screenshots/12-alb/12-alb-healthy-targets.png)<br>[`12-alb-unhealthy-target.png`](../screenshots/12-alb/12-alb-unhealthy-target.png)<br>[`12-alb-failover-working.png`](../screenshots/12-alb/12-alb-failover-working.png)<br>[`12-alb-recovered.png`](../screenshots/12-alb/12-alb-recovered.png)<br>[`12-alb-working-page.png`](../screenshots/12-alb/12-alb-working-page.png)<br>[`12-alb-app-b.png`](../screenshots/12-alb/12-alb-app-b.png) | **Verified** |
| **SEC-13** | **Edge Protection, HTTPS Enforcement & Origin Header Gating** | AWS CloudFront & ALB | Eavesdropping on viewer connections; bypass of CloudFront caching and rate-limiting policies. | CloudFront distribution configured with `redirect-to-https` viewer protocol policy. Injects a 32-character secret `X-Origin-Verify` header. ALB listener default action returns `403 Forbidden` for direct requests; forward action triggers only when header matches. Browser HTTPS access verified; access logs delivered via CloudFront Standard Logging v2. | [`13-cloudfront-https-working.png`](../screenshots/13-cloudfront/13-cloudfront-https-working.png)<br>[`13-cloudfront-alb-denied.png`](../screenshots/13-cloudfront/13-cloudfront-alb-denied.png)<br>[`13-cloudfront-403-status.png`](../screenshots/13-cloudfront/13-cloudfront-403-status.png)<br>[`13-cloudfront-logging.png`](../screenshots/13-cloudfront/13-cloudfront-logging.png) | **Verified** |
| **SEC-14** | **Centralized Management Audit Logging** | AWS CloudTrail | Undetected API modifications, administrative credential misuse, unauthorized security group or IAM changes. | Multi-region trail `depi-sec-trail` with log file validation, management events (Read/Write: All), and S3 read data events for `depi-sec-app-*`. Delivers logs to central S3 logs bucket (`depi-sec-logs-*`) and CloudWatch Log Group `/aws/cloudtrail/depi-sec-trail` (14-day retention) via IAM role `depi-sec-cloudtrail-cw-role`. S3 bucket policy enforces `aws:SourceArn` restriction and `bucket-owner-full-control`. | [`14-cloudtrail-settings.png`](../screenshots/14-cloudtrail/14-cloudtrail-settings.png)<br>[`14-cloudtrail-event-identity.png`](../screenshots/14-cloudtrail/14-cloudtrail-event-identity.png) | **Verified** |
| **SEC-15** | **VPC Flow Logs & Network Traffic Auditing** | Amazon VPC & CloudWatch Logs | Undetected lateral network movement, unauthorized port scanning, data exfiltration, covert channel communication. | `aws_flow_log.app_vpc_flow_log` (`fl-01baa2f74df906054`) attached to `aws_vpc.app_vpc` (`vpc-0f7551daf8a303b6b`) for `traffic_type = "ALL"`, publishing to `/depi-sec/vpc/flowlogs` (14-day retention) via least-privilege role `depi-sec-vpc-flow-logs-role`. Ingested `ACCEPT` records and 4 `REJECT` records on destination TCP port 22 verified via CloudWatch Logs Insights (including internal source `10.0.11.161` to `10.0.12.241`). | [`15-flowlog-reject-record.png`](../screenshots/15-flowlogs/15-flowlog-reject-record.png) | **Verified** |
| **SEC-16** | **CloudWatch Alarms, Security Metric Filtering & Proactive Alerting** | Amazon CloudWatch & Amazon SNS | Delayed incident detection for compute CPU exhaustion, target health failure, database storage starvation, and brute-force console login attempts. | 5 CloudWatch metric alarms deployed: (1) `depi-sec-ec2-cpu-high-app-a` (>70%), (2) `depi-sec-ec2-cpu-high-app-b` (>70%), (3) `depi-sec-alb-unhealthy-hosts` (>0), (4) `depi-sec-rds-free-storage-low` (<2 GB), (5) `depi-sec-failed-console-logins-alarm` (>=3 in 5m via CloudTrail metric filter `{ ($.eventName = "ConsoleLogin") && ($.errorMessage = "Failed authentication") }`). Alerts delivered to `depi-sec-alerts` SNS topic. ALB alarm transition (`OK -> ALARM`), real email alert delivery, and recovery (`ALARM -> OK`) verified during Nginx test. Operational dashboard `depi-sec-overview` visualizes live metrics. | [`16-dashboard-overview.png`](../screenshots/16-cloudwatch/16-dashboard-overview.png)<br>[`16-alarm-unhealthy-hosts.png`](../screenshots/16-cloudwatch/16-alarm-unhealthy-hosts.png)<br>[`16-alarm-email-notification.png`](../screenshots/16-cloudwatch/16-alarm-email-notification.png) | **Verified** |
| **SEC-17** | **Event-Driven Security Auto-Remediation** | AWS Lambda, EventBridge, CloudTrail & SNS | Rogue or accidental security group modification exposing sensitive ports (TCP 22 SSH, TCP 3389 RDP) to the public internet (`0.0.0.0/0`); zero-day exposure windows. | EventBridge rule `depi-sec-remediate-open-ssh` triggers on CloudTrail `AuthorizeSecurityGroupIngress`. Python 3.12 Lambda `depi-sec-auto-remediation` assumed by least-privilege role `depi-sec-lambda-remediation-role` (strictly scoped to `ec2:DescribeSecurityGroups`, `ec2:RevokeSecurityGroupIngress` on `depi-sec-app-sg`, and `sns:Publish` on `depi-sec-alerts`). Validates event, verifies `TARGET_SECURITY_GROUP_ID`, revokes only `0.0.0.0/0` (preserving port 80 from ALB SG and internal CIDRs), handles duplicate/conflict events via active rule re-inspection, logs structured telemetry, and dispatches incident alert email. | [`17-b-rule-removed.png`](../screenshots/17-lambda/17-b-rule-removed.png)<br>[`17-c-lambda-log.png`](../screenshots/17-lambda/17-c-lambda-log.png)<br>[`17-d-sns-email.png`](../screenshots/17-lambda/17-d-sns-email.png)<br>*(Note: `17-a-rule-added.png` omitted; rule remediated live before manual capture)* | **Verified** |
| **SEC-18** | **Isolated Management Network (VPC Peering)** | AWS VPC Peering & Amazon EC2 | Direct public access for operations; unsegmented administrative tools; unauthorized ingress to application tier. | `depi-sec-tools-vpc` (`10.1.0.0/16`) connected via same-account VPC peering `pcx-066a78d3ee36e18f9`. Private route tables route inter-VPC traffic. `depi-sec-tools-sg` enforces discrete egress (TCP 80, TCP 443, ICMP to `10.0.11.0/24` & `10.0.12.0/24`). `depi-sec-private-nacl` enforces stateless rules 150–152 (inbound) and 150–151 (outbound ephemeral/ICMP reply). Keyless SSM management shares App VPC interface endpoints. | [`18-peering-active.png`](../screenshots/18-peering/18-peering-active.png)<br>[`18-app-route-table.png`](../screenshots/18-peering/18-app-route-table.png)<br>[`18-tools-route-table.png`](../screenshots/18-peering/18-tools-route-table.png)<br>[`18-peering-curl-success.png`](../screenshots/18-peering/18-peering-curl-success.png) | **Verified** |

---

## 2. In-Depth Analysis: Origin Verification Limitations

While the combination of CloudFront and ALB provides effective educational defense, security reviewers must recognize the operational limitations of this configuration:

### 2.1. Unencrypted Origin Transit (`http-only`)
- **Control Implementation:** `cloudfront.tf` defines `origin_protocol_policy = "http-only"` on port 80.
- **Risk:** Traffic between the CloudFront edge POP and the ALB travels across public internet transit networks in unencrypted HTTP. An attacker with transit-level access could eavesdrop on payloads or spoof responses.
- **Production Solution:** Attach a public TLS certificate from AWS Certificate Manager (ACM) to the ALB HTTPS listener (port 443), and set CloudFront `origin_protocol_policy = "https-only"`.

### 2.2. Header Gating vs. True Perimeter Defense
- **Control Implementation:** ALB evaluates `http_header` `X-Origin-Verify`. Direct requests trigger an immediate fixed HTTP 403 response.
- **Risk:**
  - The ALB IP addresses remain publicly reachable. Although application processing is blocked, the ALB still consumes resources processing incoming TCP and HTTP handshakes, leaving it open to direct Layer 4/7 DoS attacks.
  - If the static header string is leaked, an attacker can forge the header and reach backend EC2 instances directly.
- **Production Solution:**
  - Enforce network-layer restrictions using **AWS CloudFront Managed Prefix Lists** (`aws_ec2_managed_prefix_list`) directly in the ALB security group ingress rules, dropping all packets not originating from CloudFront IP CIDRs.
  - Deploy **AWS WAF** with rate-limiting and IP reputation rules on both CloudFront and the ALB.

---

## 3. In-Depth Analysis: VPC Flow Logs & Network Security Telemetry

As part of Task 15, comprehensive network observability is established at the root of `depi-sec-app-vpc` to provide persistent Layer 3 and Layer 4 security telemetry.

### 3.1. Flow Log Configuration & Scope
- **Resource Identifier:** `aws_flow_log.app_vpc_flow_log` (Flow Log ID: `fl-01baa2f74df906054`).
- **Attachment Scope:** Attached directly to VPC `vpc-0f7551daf8a303b6b`. Monitoring at the VPC root automatically monitors every Elastic Network Interface (ENI) across all subnets (ALB nodes, EC2 app instances, RDS MySQL, EFS mount points, and VPC endpoints).
- **Independent Collection:** Flow logs collect network traffic metadata independently of guest operating system and application logging mechanisms, ensuring network visibility even if in-guest logging fails or is disabled.
- **Traffic Capture:** `traffic_type = "ALL"`, ensuring both permitted traffic (`ACCEPT`) and dropped packets (`REJECT`) are recorded.
- **Log Destination:** Amazon CloudWatch Log Group `/depi-sec/vpc/flowlogs` with a 14-day retention window. Delivery status is confirmed as `SUCCESS`.
- **Service Delegation:** Assumes IAM role `depi-sec-vpc-flow-logs-role` (`vpc-flow-logs.amazonaws.com`) with policy `depi-sec-vpc-flow-logs-policy` strictly scoped to the log group ARN.

### 3.2. Telemetry Structure & Default Fields
Telemetry is ingested using the 14 standard space-delimited fields:
`version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes start end action log-status`

### 3.3. Empirical Audit Evidence & Findings
CloudWatch Logs Insights query explicitly scoped to `/depi-sec/vpc/flowlogs`:
```text
fields @timestamp, @message
| parse @message "* * * * * * * * * * * * * *" as version, account, eni, srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes, startTime, endTime, action, logStatus
| filter dstport = "22" and action = "REJECT"
| sort @timestamp desc
| limit 20
```

- **Observed Findings:**
  1. **Operational Traffic Delivery:** Ingested flow records show active `ACCEPT` entries for authorized HTTP application traffic (ALB -> EC2), EFS NFS storage access (EC2 -> EFS port 2049), and SSM management sessions (EC2 -> VPC endpoints port 443).
  2. **External Inbound Reconnaissance:** Three `REJECT` records documented internet sources (`46.109.171.236`, `193.163.125.173`) scanning destination port 22 on public ALB interfaces (`10.0.2.49`, `10.0.1.109`).
  3. **Internal Lateral Movement Attempt:** One `REJECT` record documented an internal connection attempt originating from `depi-sec-app-a` (`10.0.11.161`) targeting `depi-sec-app-b` (`10.0.12.241`) on destination TCP port 22. At the client probe layer, this connection attempt timed out with exit code `124`, matching the recorded flow log REJECT entry:
     `2 882034443616 eni-0b401abe98593901c 10.0.11.161 10.0.12.241 58932 22 6 3 180 1792100814 1792100825 REJECT OK`

### 3.4. Security Boundary & Attribution Boundary
VPC Flow Logs record the packet evaluation decision (`REJECT`) at the network interface layer.
- **Verification Scope:** This validation confirms Layer 4 TCP network isolation. It is distinct from a full interactive SSH authentication test (negotiating host keys, testing user credentials, or opening a shell session), which was not performed because instances have no open port 22 and are managed keylessly via AWS Systems Manager Session Manager.
- **Rule Attribution Boundary:** While the log conclusively verifies that unauthorized port 22 traffic was dropped at the network interface, flow log records do not differentiate whether the drop was enforced by the stateless Network ACL (`depi-sec-private-nacl` Inbound Rule 200) or by the stateful Security Group (`depi-sec-app-sg`), as both security controls strictly prohibit inbound TCP port 22.

---

## 4. In-Depth Analysis: CloudWatch Observability, Metric Filtering & SNS Alerting (Task 16)

As part of Task 16, proactive monitoring and real-time operational observability are established across compute, load balancing, relational database, and governance tiers.

### 4.1. Proactive Metric Alarms & Telemetry Structure
Five CloudWatch metric alarms continuously evaluate infrastructure health and security posture:
- **Compute Load Alarms:** `depi-sec-ec2-cpu-high-app-a` and `depi-sec-ec2-cpu-high-app-b` independently evaluate instances `i-0749711e008057ae1` and `i-0306fb121beae9963` for `CPUUtilization > 70%` over 2 consecutive 5-minute periods (`evaluation_periods = 2`, `datapoints_to_alarm = 2`, `statistic = "Average"`, `treat_missing_data = "notBreaching"`).
- **ALB Target Group Health Alarm:** `depi-sec-alb-unhealthy-hosts` evaluates `UnHealthyHostCount > 0` over 60 seconds across dimensions `TargetGroup` (`depi-sec-tg`) and `LoadBalancer` (`depi-sec-alb`). Dispatches alert notifications upon breach and recovery notifications (`ok_actions`) upon target restoration.
- **RDS Database Capacity Alarm:** `depi-sec-rds-free-storage-low` evaluates `FreeStorageSpace < 2147483648` Bytes (2 GB) on `depi-sec-db` over 300 seconds (`statistic = "Average"`).
- **Security Failed Console Login Alarm:** `depi-sec-failed-console-logins-alarm` evaluates security events extracted from CloudTrail, firing if 3 or more authentication failures occur within 5 minutes (`threshold = 3`, `period = 300`, `statistic = "Sum"`).

### 4.2. Security Metric Filtering on CloudTrail Audit Logs
Attached to `/aws/cloudtrail/depi-sec-trail`, metric filter `depi-sec-failed-console-logins-filter` parses management event JSON payloads using exact pattern:
```text
{ ($.eventName = "ConsoleLogin") && ($.errorMessage = "Failed authentication") }
```
Matches are published to metric `FailedConsoleLogins` under namespace `depi-sec/Security` with value `1` and default `0`, enabling automated alarm triggering on potential brute-force or unauthorized credential stuffing attacks.

### 4.3. SNS Topic Policy & Least-Privilege Access Control
Alert topic `depi-sec-alerts` attaches policy `depi-sec-alerts-policy`:
- **Owning Account Administration:** Statement `AllowAccountOwnerManageTopic` grants `arn:aws:iam::<account-id>:root` topic management actions (`sns:GetTopicAttributes`, `sns:SetTopicAttributes`, `sns:AddPermission`, `sns:RemovePermission`, `sns:DeleteTopic`, `sns:Subscribe`, `sns:ListSubscriptionsByTopic`, `sns:Publish`).
- **CloudWatch Service Delegation:** Statement `AllowCloudWatchAlarmsPublish` restricts `sns:Publish` strictly to service principal `cloudwatch.amazonaws.com` conditioned on `StringEquals: { "aws:SourceAccount": "<account-id>" }`. Public (`*`) and cross-account access are strictly prohibited.

### 4.4. SNS Encryption Architecture Decision
The SNS topic is intentionally configured without AWS-managed KMS encryption (`alias/aws/sns`):
- CloudWatch Alarms cannot publish to topics encrypted with default AWS-managed KMS keys because default KMS key policies are immutable and cannot grant `kms:GenerateDataKey*` or `kms:Decrypt` permissions to `cloudwatch.amazonaws.com`.
- Overcoming this requires provisioning a Customer Managed Key (CMK), incurring a fixed fee of $1.00/month (10% of the project's $10 budget).
- Maintaining an unencrypted topic at the SNS service level guarantees alarm delivery and avoids recurring CMK charges, with security enforced by least-privilege resource policies and TLS transit encryption.

### 4.5. Operations Dashboard (`depi-sec-overview`)
The CloudWatch dashboard consolidates real-time telemetry into four widgets:
1. `EC2 Compute CPU Utilization (%)` with threshold line at 70%.
2. `ALB Target Group UnHealthy Hosts` with threshold line at > 0.
3. `RDS Database Free Storage Space` with threshold line at 2 GB (`2,147,483,648` Bytes).
4. `Security: CloudTrail Failed Console Logins` with threshold line at >= 3.

---

## 5. In-Depth Analysis: Event-Driven Security Auto-Remediation (Task 17)

As part of Task 17, automated incident response capabilities are established to enforce continuous compliance against unauthorized security group rule modifications.

### 5.1. Remediation Architecture & Execution Control Plane
- **Detection Trigger:** AWS CloudTrail captures management write event `AuthorizeSecurityGroupIngress` across the AWS account and forwards audit events to the default Amazon EventBridge bus.
- **Event Filter:** EventBridge rule `depi-sec-remediate-open-ssh` filters events matching source `aws.ec2` and event name `AuthorizeSecurityGroupIngress`.
- **Target Invocation:** Directly triggers AWS Lambda function `depi-sec-auto-remediation` (Python 3.12 runtime) via resource-based invoke policy `AllowExecutionFromEventBridge`.

### 5.2. Least-Privilege IAM Boundary
The Lambda execution role (`depi-sec-lambda-remediation-role`) adheres strictly to least-privilege principles without wildcard administrative permissions:
1. `ec2:DescribeSecurityGroups`: Allows querying security group rule definitions across the region (required because EC2 Describe APIs do not support resource-level permissions).
2. `ec2:RevokeSecurityGroupIngress`: Scoped strictly to the target application security group ARN (`arn:aws:ec2:us-east-1:<account-id>:security-group/sg-045206e75cb53b510`). The function is cryptographically blocked by IAM from revoking rules on database, ALB, or external security groups.
3. `sns:Publish`: Scoped strictly to the topic ARN `arn:aws:sns:us-east-1:<account-id>:depi-sec-alerts`.
4. CloudWatch Logs: Scoped strictly to log group `/aws/lambda/depi-sec-auto-remediation:*`.

### 5.3. Discrete CIDR Revocation vs. Rule Destruction
- **Inspection Logic:** The Python handler inspects all `IpPermissions` on the security group for rules matching public IPv4 CIDR `0.0.0.0/0` on sensitive administrative ports: TCP 22 (SSH), TCP 3389 (RDP), overlapping ranges (e.g., 20–25, 3000–4000), or all-traffic protocol `-1`.
- **Preservation of Legitimate Rules:** When a dangerous rule is identified, the revocation payload specifies **only** `IpRanges: [{"CidrIp": "0.0.0.0/0"}]` for that specific protocol and port range. Legitimate internal network CIDRs (e.g., `10.0.0.0/16`) and security group references (ALB SG on port 80) within the same rule set remain completely untouched.

### 5.4. Defensive Race Conditions & Duplicate Event Handling
- **Event Envelope Validation:** The handler validates the incoming EventBridge structure and ignores failed CloudTrail events containing `errorCode` or `errorMessage` (where no rules were actually added).
- **Target Scoping:** The handler validates the security group ID against regex `^sg-[0-9a-fA-F]{8,17}$` and verifies against `TARGET_SECURITY_GROUP_ID`.
- **Re-Inspection on Conflict:** If `ec2:RevokeSecurityGroupIngress` encounters `InvalidPermission.NotFound` (due to duplicate event delivery or concurrent remediation), the function re-describes the security group. If no dangerous rules remain, it confirms `ALREADY_CLEAN` and suppresses redundant SNS notifications; if dangerous rules remain, it logs `FAILED_DANGEROUS_RULES_REMAIN` without falsely reporting success.

### 5.5. Observability, Latency & Scope Boundaries
- **CloudTrail Delivery Window:** AWS CloudTrail delivers management events to EventBridge with an inherent delivery latency of approximately 30 to 60 seconds. Auto-remediation is a near-real-time compensating control rather than an inline packet firewall.
- **Dedicated Log Group:** Execution logs are retained in `/aws/lambda/depi-sec-auto-remediation` with a 14-day retention window, logging structured JSON events without exposing sensitive credentials or raw CloudTrail request payloads.

---

## 6. In-Depth Analysis: Isolated Management Network & VPC Peering (Task 18)

As part of Task 18, enterprise-grade network segmentation and out-of-band management isolation are established by connecting an isolated Tools VPC to the primary Application VPC via a secure VPC Peering connection.

### 6.1. Network Segmentation & VPC Peering Architecture
- **Isolated Tools VPC:** `aws_vpc.tools_vpc` (`depi-sec-tools-vpc`, CIDR `10.1.0.0/16`) deployed in `us-east-1` with DNS support and DNS hostnames enabled. Completely non-overlapping with the App VPC CIDR (`10.0.0.0/16`).
- **Private Subnet Isolation:** Subnet `depi-sec-tools-a` (`10.1.1.0/24`) in AZ `us-east-1a` is configured with `map_public_ip_on_launch = false`. The VPC contains no Internet Gateway, NAT Gateway, or public subnets, eliminating external attack vectors.
- **Same-Account VPC Peering:** `aws_vpc_peering_connection.peering` (`depi-sec-app-tools-peering`, `pcx-066a78d3ee36e18f9`) connects `aws_vpc.app_vpc` (requester) and `aws_vpc.tools_vpc` (accepter) with `auto_accept = true`.
- **Non-Transitive Network Boundary:** AWS VPC Peering is strictly non-transitive. The Tools VPC cannot be leveraged as a transit path to any external networks or subsequent peerings, preserving absolute isolation.

### 6.2. Bidirectional Route Table Configuration
Routing between the two VPCs is strictly restricted to private route tables:
- **App Private Route Table (`depi-sec-private-rt`):** Routes `10.1.0.0/16` via VPC Peering connection `pcx-066a78d3ee36e18f9` with status `Active`.
- **Tools Private Route Table (`depi-sec-tools-rt`):** Routes `10.0.0.0/16` via VPC Peering connection `pcx-066a78d3ee36e18f9` with status `Active`. Associated strictly with subnet `depi-sec-tools-a`.
- **Public Subnet Exclusion:** The App VPC public route table contains no routes to `10.1.0.0/16`, ensuring that external edge components cannot reach the management tier.

### 6.3. Discrete Least-Privilege Security Group Egress
Security group `depi-sec-tools-sg` implements discrete, least-privilege egress rules instead of broad VPC-wide CIDR permissions:
- **Egress to App Private Subnets:**
  - TCP port 80 (HTTP) to `10.0.11.0/24` (`depi-sec-private-a`) and `10.0.12.0/24` (`depi-sec-private-b`).
  - ICMP Echo (ping) to `10.0.11.0/24` and `10.0.12.0/24`.
- **Egress to SSM Interface Endpoints:**
  - TCP port 443 (HTTPS) to `10.0.11.0/24` and `10.0.12.0/24`.
- **Zero Internet Egress:** No `0.0.0.0/0` outbound rule exists; outbound connectivity is restricted entirely to the peering interface.
- **Inbound Permissions on Target Security Groups:**
  - `depi-sec-app-sg`: Permits inbound TCP port 80 and ICMP strictly from Tools subnet CIDR `10.1.1.0/24`.
  - `depi-sec-endpoint-sg`: Permits inbound TCP port 443 strictly from Tools subnet CIDR `10.1.1.0/24`.

### 6.4. Stateless Subnet Boundary Defense (Network ACL Rules)
Because Network ACLs are stateless, return traffic must be explicitly accounted for in both directions. In Network ACL `depi-sec-private-nacl` attached to the App VPC private subnets:
- **Inbound Rules:**
  - Rule 150: Allow TCP port 80 from `10.1.1.0/24` (App web service ingress).
  - Rule 151: Allow ICMP type -1 code -1 from `10.1.1.0/24` (Diagnostic ping ingress).
  - Rule 152: Allow TCP port 443 from `10.1.1.0/24` (SSM Interface Endpoint ingress).
- **Outbound Rules:**
  - Rule 150: Allow TCP ports 1024–65535 to `10.1.1.0/24` (Ephemeral return packets for HTTP and HTTPS sessions).
  - Rule 151: Allow ICMP type -1 code -1 to `10.1.1.0/24` (ICMP Echo Reply return packets).

This ensures that administrative traffic from the Tools VPC is permitted at the network perimeter without opening broad IP blocks or compromising existing Rule 200 (deny public SSH).

### 6.5. Keyless SSM Management via Shared Interface Endpoints
The Tools EC2 instance (`depi-sec-tools-instance`, `i-039ddfc570cb61341`) is managed keylessly without SSH keys, public IPs, or internet access:
- **IAM Instance Profile:** Reuses `depi-sec-ec2-instance-profile` with `AmazonSSMManagedInstanceCore`.
- **Cross-Peering Endpoint Sharing:** Rather than provisioning dedicated VPC Interface Endpoints in the Tools VPC (which would incur an extra $21.60/month across 3 endpoints), the Tools instance connects to the existing SSM interface endpoints in the App VPC across VPC Peering.
- **Dynamic User Data Configuration:** The EC2 `user_data` script dynamically resolves the endpoint private DNS names (`aws_vpc_endpoint.*.dns_entry[0].dns_name`), adds hostname overrides in `/etc/hosts` for `ssm.us-east-1.amazonaws.com`, `ssmmessages.us-east-1.amazonaws.com`, and `ec2messages.us-east-1.amazonaws.com`, and restarts the `amazon-ssm-agent`.
- **Operational Verification:** SSM connection status confirmed as `Online`, allowing secure interactive terminal access exclusively via AWS Systems Manager Session Manager.

---

## 7. Pending Security Controls (Tasks 19–20)

The following controls represent outstanding project tasks that have not yet been implemented or deployed in Terraform:

| Task | Control | Planned AWS Service | Planned Threat Mitigation | Current Status |
| :--- | :--- | :--- | :--- | :--- |
| **Task 19** | **Immutable Ransomware-Resistant Backups** | AWS Backup (Vault Lock) | Ransomware deletion of snapshots, accidental administrator destruction of backups. | *Pending implementation in `backup.tf`* |
| **Task 20** | **End-to-End Security Audit & Clean Destroy** | Terraform CLI & AWS Console | Unmonitored lingering infrastructure, resource leakage, cost overruns. | *Pending final execution after Task 19* |
