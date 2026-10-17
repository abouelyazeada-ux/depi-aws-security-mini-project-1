# Security Testing & Verification Report — Tasks 1–18

This document records the empirical validation of the security controls implemented in **Tasks 1–18**, following the standardized test framework outlined in **Task 20** of `Project-1.pdf`.

Each test case details the operational procedure performed, the expected security outcome, the observed real-world behavior, and links to the supporting screenshot evidence. Tests are strictly documented based on confirmed evidence without assuming or inferring unexecuted steps. Tests associated with **Tasks 19–20** that require pending infrastructure are explicitly identified as **Pending Implementation**.

---

## Test Execution Summary Matrix

| # | Test Case Description | Target Component | Expected Result | Actual Outcome | Status | Evidence Link |
| :-: | :--- | :--- | :--- | :--- | :-: | :--- |
| **1** | Open ALB DNS name directly in browser / CLI | Application Load Balancer (`depi-sec-alb`) | HTTP `403 Forbidden` | Returned HTTP 403 status code and body `"Access Denied"` | **PASS** | [`13-cloudfront-alb-denied.png`](../screenshots/13-cloudfront/13-cloudfront-alb-denied.png)<br>[`13-cloudfront-403-status.png`](../screenshots/13-cloudfront/13-cloudfront-403-status.png) |
| **2** | Open CloudFront distribution URL | AWS CloudFront (`depi-sec-cloudfront`) | Page loads over HTTPS | Loaded `https://dfj4o8x4memfi.cloudfront.net` displaying backend page | **PASS** | [`13-cloudfront-https-working.png`](../screenshots/13-cloudfront/13-cloudfront-https-working.png) |
| **3** | Direct SSH attempt to private EC2 instance | EC2 Application Tier & VPC Flow Logs | Inbound SSH blocked; REJECT record in VPC Flow Logs | Zero public IPs; internal TCP port 22 probe from 10.0.11.161 to 10.0.12.241 timed out (exit code 124); CloudWatch Logs Insights confirmed 4 REJECT records on TCP port 22; validates TCP network isolation without definitive rule attribution (interactive SSH authentication not tested) | **PASS (Network Isolation & Flow Log REJECT Verified)** | [`08-ec2-app-a-no-public-ip.png`](../screenshots/08-session-manager/08-ec2-app-a-no-public-ip.png)<br>[`08-ec2-app-b-no-public-ip.png`](../screenshots/08-session-manager/08-ec2-app-b-no-public-ip.png)<br>[`06-nacl-inbound-rules.png`](../screenshots/06-nacl/06-nacl-inbound-rules.png)<br>[`15-flowlog-reject-record.png`](../screenshots/15-flowlogs/15-flowlog-reject-record.png) |
| **4** | Direct connection to RDS from external client | Amazon RDS MySQL (`depi-sec-db`) | Connection fails / timeout | PowerShell `Test-NetConnection` to port 3306 failed (`TcpTestSucceeded : False`) | **PASS** | [`11-rds-external-connection-failed.png`](../screenshots/11-rds/11-rds-external-connection-failed.png)<br>[`11-rds-private-access.png`](../screenshots/11-rds/11-rds-private-access.png) |
| **5** | TCP connection to RDS from internal EC2 instance | Amazon RDS MySQL (`depi-sec-db`) | Port 3306 reachable | Bash `/dev/tcp` probe confirmed: `SUCCESS: RDS port 3306 is reachable` | **PASS (Network Reachability)** | [`11-rds-internal-connection.png`](../screenshots/11-rds/11-rds-internal-connection.png) |
| **6** | Anonymous / public access to S3 test object | Amazon S3 (`depi-sec-app-*`) | Access denied / refused | Unauthenticated `curl -I` returned `HTTP/1.1 403 Forbidden`; explicit ACL mutation **not executed** | **PASS (Anonymous Read Refusal) / PARTIAL** | [`10-s3-public-access-refused.png`](../screenshots/10-s3/10-s3-public-access-refused.png)<br>[`10-app-bucket-public-access-block.png`](../screenshots/10-s3/10-app-bucket-public-access-block.png) |
| **7** | Add SSH rule (`0.0.0.0/0:22`) to App SG | Security Auto-Remediation (Lambda & EventBridge) | Rogue rule removed by Lambda; HTTP port 80 preserved; CloudWatch log and SNS email received | Port 22 from `0.0.0.0/0` manually authorized on `depi-sec-app-sg`; EventBridge event triggered Lambda; CloudWatch logs confirmed `REMEDIATION_TRIGGERED`, `REMEDIATION_SUCCESS`, and `SNS_ALERT_PUBLISHED`; rule revoked; original HTTP port 80 rule remained intact; real SNS email alert received | **PASS (Automated Remediation Verified; Before Screenshot Omitted)** | [`17-b-rule-removed.png`](../screenshots/17-lambda/17-b-rule-removed.png)<br>[`17-c-lambda-log.png`](../screenshots/17-lambda/17-c-lambda-log.png)<br>[`17-d-sns-email.png`](../screenshots/17-lambda/17-d-sns-email.png) |
| **8** | Stop Nginx web service on one instance | ALB Target Group (`depi-sec-tg`) & CloudWatch Alarms | Target marked Unhealthy; traffic routes to healthy target; CloudWatch alarm fires; alert email sent | `app-a` marked Unhealthy in console; traffic served by `app-b`; CloudWatch alarm `depi-sec-alb-unhealthy-hosts` transitioned to `ALARM`; real SNS alert email received; `depi-sec-overview` dashboard captured spike to 1 and recovery to 0; returned to Healthy | **PASS** | [`12-alb-unhealthy-target.png`](../screenshots/12-alb/12-alb-unhealthy-target.png)<br>[`12-alb-failover-working.png`](../screenshots/12-alb/12-alb-failover-working.png)<br>[`12-alb-recovered.png`](../screenshots/12-alb/12-alb-recovered.png)<br>[`16-alarm-unhealthy-hosts.png`](../screenshots/16-cloudwatch/16-alarm-unhealthy-hosts.png)<br>[`16-alarm-email-notification.png`](../screenshots/16-cloudwatch/16-alarm-email-notification.png)<br>[`16-dashboard-overview.png`](../screenshots/16-cloudwatch/16-dashboard-overview.png) |
| **9** | Curl app server from peering tools VPC | VPC Peering Connection (`pcx-066a78d3ee36e18f9`) | HTTP 200 via private route | Executed `curl -s -o /dev/null -w "%{http_code}" http://10.0.11.161` from Tools EC2 (`i-039ddfc570cb61341`); returned HTTP 200 OK over private route via active peering connection; direct external ALB access returned HTTP 403 Forbidden | **PASS** | [`18-peering-active.png`](../screenshots/18-peering/18-peering-active.png)<br>[`18-app-route-table.png`](../screenshots/18-peering/18-app-route-table.png)<br>[`18-tools-route-table.png`](../screenshots/18-peering/18-tools-route-table.png)<br>[`18-peering-curl-success.png`](../screenshots/18-peering/18-peering-curl-success.png) |
| **10** | Delete recovery point in locked backup vault | AWS Backup Vault Lock | Access Denied by Vault Lock | *Pending Task 19 Backup deployment* | **PENDING** | *Awaiting Task 19* |

---

## Detailed Test Procedures & Empirical Results

### Test 1: Direct Access Attempt to Application Load Balancer
- **Objective:** Verify that direct public HTTP requests to the Application Load Balancer bypassing CloudFront are refused.
- **Empirical Evidence & Observed Procedure:**
  1. A `curl.exe` command was executed targeting the ALB DNS name directly without the origin verification header:
     ```cmd
     curl.exe -s -o NUL -w "%{http_code}" http://depi-sec-alb-1246520704.us-east-1.elb.amazonaws.com
     ```
  2. The ALB URL (`http://depi-sec-alb-1246520704.us-east-1.elb.amazonaws.com`) was opened directly in a web browser.
- **Expected Outcome:** HTTP `403 Forbidden` status code with response body `"Access Denied"`.
- **Actual Result:**
  - `curl.exe` returned HTTP status code `403`.
  - The browser session rendered `"Access Denied"`.
  - Both observations confirm that ALB listener rule #1 rejected the direct request and executed the default fixed response action.
- **Screenshots:**
  - [`13-cloudfront-403-status.png`](../screenshots/13-cloudfront/13-cloudfront-403-status.png) — Command line output showing HTTP status code `403`.
  - [`13-cloudfront-alb-denied.png`](../screenshots/13-cloudfront/13-cloudfront-alb-denied.png) — Browser displaying `"Access Denied"` on the direct ALB URL.

---

### Test 2: Access via CloudFront Distribution over HTTPS
- **Objective:** Confirm that the web application is accessible through the CloudFront distribution domain over HTTPS.
- **Empirical Evidence & Observed Procedure:**
  1. Navigated to the CloudFront distribution domain in a browser:
     ```
     https://dfj4o8x4memfi.cloudfront.net
     ```
- **Expected Outcome:** The page loads over HTTPS and displays the application content.
- **Actual Result:**
  - The browser established a secure HTTPS connection (indicated by the lock icon in the address bar).
  - The application HTML rendered successfully, displaying:
    - Page Title: `depi-sec-app-b`
    - Header: `depi-sec-app-b`
    - Availability Zone: `AZ: us-east-1b`
- **Screenshots:**
  - [`13-cloudfront-https-working.png`](../screenshots/13-cloudfront/13-cloudfront-https-working.png) — Web browser displaying the application page over HTTPS via CloudFront.

---

### Test 3: Direct SSH Ingress Verification
- **Objective:** Confirm whether the private EC2 instances have public IP addresses, whether network security boundaries restrict inbound SSH traffic, and whether dropped packets generate `REJECT` records in VPC Flow Logs.
- **Empirical Evidence & Observed Procedure:**
  1. EC2 instance configuration was inspected in the AWS Management Console and CLI:
     - Instance `depi-sec-app-a` (`i-0749711e008057ae1`): Public IPv4 address is empty (`-`). Private IP is `10.0.11.161`.
     - Instance `depi-sec-app-b` (`i-0306fb121beae9963`): Public IPv4 address is empty (`-`). Private IP is `10.0.12.241`.
  2. Network ACL `depi-sec-private-nacl` configuration was inspected in the AWS Console:
     - Inbound Rule 200 explicitly sets: Protocol: `TCP (6)`, Port range: `22`, Source: `0.0.0.0/0`, Allow/Deny: `DENY`. In addition, security group `depi-sec-app-sg` restricts ingress strictly to TCP port 80 from `depi-sec-alb-sg`.
  3. VPC Flow Logs (`fl-01baa2f74df906054`) was enabled at the VPC level on `aws_vpc.app_vpc` (`vpc-0f7551daf8a303b6b`) with traffic type `ALL`, publishing to CloudWatch Log Group `/depi-sec/vpc/flowlogs`.
  4. Flow log delivery status was verified as `SUCCESS`, with active `ACCEPT` records observed for legitimate application and endpoint communications.
  5. A TCP connection attempt targeting destination TCP port 22 was initiated from `depi-sec-app-a` (`10.0.11.161`) toward `depi-sec-app-b` (`10.0.12.241`). The probe timed out with exit code `124`, confirming that SYN packets were dropped without establishing a TCP connection.
  6. A CloudWatch Logs Insights query explicitly scoped to log group `/depi-sec/vpc/flowlogs` was executed to filter for TCP port 22 traffic:
     ```text
     fields @timestamp, @message
     | parse @message "* * * * * * * * * * * * * *" as version, account, eni, srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes, startTime, endTime, action, logStatus
     | filter dstport = "22" and action = "REJECT"
     | sort @timestamp desc
     | limit 20
     ```
  7. The query returned four distinct `REJECT` records on destination port 22:
     - Three external scanning attempts from public IPs (`46.109.171.236`, `193.163.125.173`) targeting port 22 on ALB public interfaces (`10.0.2.49`, `10.0.1.109`).
     - One internal connection attempt originating from `depi-sec-app-a` (`10.0.11.161`) targeting `depi-sec-app-b` (`10.0.12.241`) on destination TCP port 22, matching the timed-out probe:
       `2 882034443616 eni-0b401abe98593901c 10.0.11.161 10.0.12.241 58932 22 6 3 180 1792100814 1792100825 REJECT OK`
  8. *Execution Status & Verification Scope:*
     - **TCP Network Isolation vs. Interactive SSH Test:** This empirical test verifies Layer 4 TCP network isolation. Packets targeting port 22 are rejected at the network interface boundary. A full interactive SSH authentication test (negotiating cryptographic ciphers, validating host keys or SSH credentials, and opening an interactive shell) was neither attempted nor executed, as the host does not expose port 22 and administrative access is exclusively managed keylessly via AWS Systems Manager Session Manager.
     - **Rule Attribution Boundary:** VPC Flow Logs record the packet drop decision (`action = "REJECT"`) at the ENI boundary. The evidence does not attribute the drop definitively to a specific NACL or Security Group: both the stateless Network ACL (`depi-sec-private-nacl` Inbound Rule 200 DENY 22) and the stateful Security Group (`depi-sec-app-sg`, which does not permit inbound port 22) enforce drops on this traffic.
- **Expected Outcome:** Instances cannot be reached via direct internet SSH, and dropped connection attempts are recorded as `REJECT` entries in VPC Flow Logs.
- **Actual Result:** Confirmed that neither instance has a public IP address, inbound TCP port 22 connection attempts time out with exit code 124, and CloudWatch Logs Insights verified four `REJECT` records on TCP port 22 (including source `10.0.11.161` targeting `10.0.12.241`).
- **Status:** **PASS (Network Isolation & Flow Log REJECT Verified)**
- **Screenshots:**
  - [`08-ec2-app-a-no-public-ip.png`](../screenshots/08-session-manager/08-ec2-app-a-no-public-ip.png) — AWS Console showing `depi-sec-app-a` with no public IPv4 address (`-`).
  - [`08-ec2-app-b-no-public-ip.png`](../screenshots/08-session-manager/08-ec2-app-b-no-public-ip.png) — AWS Console showing `depi-sec-app-b` with no public IPv4 address (`-`).
  - [`06-nacl-inbound-rules.png`](../screenshots/06-nacl/06-nacl-inbound-rules.png) — AWS Console showing `depi-sec-private-nacl` Inbound Rule 200 DENY TCP 22.
  - [`15-flowlog-reject-record.png`](../screenshots/15-flowlogs/15-flowlog-reject-record.png) — CloudWatch Logs Insights showing `REJECT` records on destination port 22.

---

### Test 4: External Connection Attempt to RDS MySQL
- **Objective:** Verify that the RDS MySQL instance cannot be reached over the network from an external client.
- **Empirical Evidence & Observed Procedure:**
  1. A network connection test was executed from a local PowerShell terminal targeting the RDS endpoint on TCP port 3306:
     ```powershell
     Test-NetConnection -ComputerName depi-sec-db.c27aqe4u6puq.us-east-1.rds.amazonaws.com -Port 3306
     ```
  2. The RDS instance configuration was inspected in the AWS Management Console.
- **Expected Outcome:** TCP connection attempt fails; RDS instance is marked as not publicly accessible.
- **Actual Result:**
  - The PowerShell command resolved the endpoint to private IP `10.0.12.157` and reported:
    - `PingSucceeded : False`
    - `TcpTestSucceeded : False`
  - The AWS Console confirmed: `Publicly accessible: No`.
- **Status:** **PASS**
- **Screenshots:**
  - [`11-rds-external-connection-failed.png`](../screenshots/11-rds/11-rds-external-connection-failed.png) — PowerShell terminal showing `TcpTestSucceeded : False`.
  - [`11-rds-private-access.png`](../screenshots/11-rds/11-rds-private-access.png) — RDS Console displaying `Publicly accessible: No`.

---

### Test 5: Internal TCP Connectivity to RDS MySQL from App Server
- **Objective:** Verify that an internal EC2 instance in the private subnet can establish TCP network connectivity to the RDS instance on port 3306.
- **Empirical Evidence & Observed Procedure:**
  1. Connected to `depi-sec-app-a` (`i-0749711e008057ae1`) via AWS Systems Manager Session Manager.
  2. Executed a bash TCP socket probe to verify reachability on port 3306:
     ```bash
     timeout 5 bash -c 'echo > /dev/tcp/depi-sec-db.c27aqe4u6puq.us-east-1.rds.amazonaws.com/3306' && echo "SUCCESS: RDS port 3306 is reachable" || echo "FAILED: RDS port 3306 is unreachable"
     ```
  3. *Note on Scope:* This test validated **TCP port reachability** at the network/firewall layer. MySQL client authentication, credential validation, or SQL queries (`SELECT VERSION()`, `SHOW DATABASES;`) were not executed in this recorded session.
- **Expected Outcome:** Port 3306 accepts TCP connection requests from the application instance.
- **Actual Result:** The probe completed successfully and printed:
  `SUCCESS: RDS port 3306 is reachable`
- **Status:** **PASS (Network Reachability)**
- **Screenshots:**
  - [`11-rds-internal-connection.png`](../screenshots/11-rds/11-rds-internal-connection.png) — Session Manager terminal on `depi-sec-app-a` displaying `SUCCESS: RDS port 3306 is reachable`.

---

### Test 6: S3 Object Public Access Verification
- **Objective:** Verify that objects stored in the application S3 bucket cannot be accessed anonymously over the public internet.
- **Empirical Evidence & Observed Procedure:**
  1. A test file named `s3-public-test.txt` was uploaded privately to the application bucket (`depi-sec-app-75d8770a`).
  2. S3 Object Ownership was verified as **Bucket owner enforced**, meaning access control lists (ACLs) are disabled.
  3. Amazon S3 Block Public Access was active (all 4 settings enabled).
  4. An unauthenticated HTTP HEAD request was issued from a local command prompt targeting the object URL:
     ```cmd
     curl.exe -I https://depi-sec-app-75d8770a.s3.us-east-1.amazonaws.com/s3-public-test.txt
     ```
  5. The test object was subsequently deleted, leaving zero remaining versions or delete markers.
  6. *Execution Status Note:* An explicit attempt to upload with `--acl public-read` or run `PutObjectAcl` was **NOT EXECUTED** (ACLs are disabled on the bucket).
- **Expected Outcome:** Anonymous HTTP requests to the object URL are refused with HTTP 403 Forbidden.
- **Actual Result:**
  - Amazon S3 returned:
    - `HTTP/1.1 403 Forbidden`
    - `Server: AmazonS3`
  - S3 Block Public Access and Bucket owner enforced settings successfully prevented anonymous access.
- **Status:** **PASS (Anonymous Read Refusal) / PARTIAL (Explicit ACL Mutation Not Executed)**
- **Screenshots:**
  - [`10-s3-public-access-refused.png`](../screenshots/10-s3/10-s3-public-access-refused.png) — Command line showing `HTTP/1.1 403 Forbidden` from Amazon S3.
  - [`10-app-bucket-public-access-block.png`](../screenshots/10-s3/10-app-bucket-public-access-block.png) — S3 Console displaying Block Public Access settings active.

---

### Test 7: Security Group Ingress Auto-Remediation (Task 17)
- **Objective:** Validate that an unauthorized public ingress rule (TCP port 22 from `0.0.0.0/0`) added to the application security group is automatically detected via AWS CloudTrail, routed through Amazon EventBridge, and revoked by AWS Lambda (`depi-sec-auto-remediation`), that an incident alert is published via Amazon SNS (`depi-sec-alerts`), that legitimate ingress rules (HTTP port 80 from ALB SG) remain intact, and that structured telemetry is recorded in CloudWatch Logs.
- **Empirical Evidence & Observed Procedure:**
  1. Inspected baseline ingress configuration on `depi-sec-app-sg` (`sg-045206e75cb53b510`), confirming only authorized inbound HTTP port 80 traffic from `depi-sec-alb-sg` (`sg-044c25590953c6ec3`).
  2. Manually authorized a dangerous inbound rule on `depi-sec-app-sg` via AWS Management Console:
     - Protocol: `TCP (6)`
     - Port: `22` (SSH)
     - Source: `0.0.0.0/0`
     - Description: `Manual unauthorized SSH test`
  3. AWS CloudTrail captured management event `AuthorizeSecurityGroupIngress` from service source `ec2.amazonaws.com` targeting `groupId: "sg-045206e75cb53b510"`.
  4. Amazon EventBridge rule `depi-sec-remediate-open-ssh` matched the event pattern and triggered target `AutoRemediateOpenSSH`, invoking Lambda function `depi-sec-auto-remediation`.
  5. The Lambda function executed under IAM role `depi-sec-lambda-remediation-role`:
     - Validated the event envelope and confirmed `groupId == TARGET_SECURITY_GROUP_ID`.
     - Queried active rules via `ec2:DescribeSecurityGroups`.
     - Identified the unauthorized `0.0.0.0/0:22` rule in `IpPermissions`.
     - Issued discrete `ec2:RevokeSecurityGroupIngress` to revoke **only** `0.0.0.0/0`, preserving the legitimate port 80 rule.
     - Dispatched a security alert to Amazon SNS topic `depi-sec-alerts`.
  6. Verified CloudWatch Logs stream `/aws/lambda/depi-sec-auto-remediation` confirming the complete remediation sequence:
     - `{"action": "EVENT_RECEIVED", "detail_type": "AWS API Call via CloudTrail", "event_name": "AuthorizeSecurityGroupIngress"}`
     - `{"action": "SECURITY_GROUP_INSPECTED", "security_group_id": "sg-045206e75cb53b510", "total_rules_inspected": 2}`
     - `{"action": "REMEDIATION_TRIGGERED", "security_group_id": "sg-045206e75cb53b510", "offending_rules_count": 1}`
     - `{"action": "REMEDIATION_SUCCESS", "security_group_id": "sg-045206e75cb53b510", "revoked_rules_count": 1}`
     - `{"action": "SNS_ALERT_PUBLISHED", "topic_arn": "arn:aws:sns:us-east-1:882034443616:depi-sec-alerts", "subject": "[AUTO-REMEDIATION] Revoked open ingress on sg-045206e75cb53b510"}`
  7. Re-inspected `depi-sec-app-sg` in the EC2 Console: confirmed the SSH rule was completely gone, and the original HTTP port 80 rule from `depi-sec-alb-sg` remained fully intact.
  8. Confirmed receipt of an automated email alert in the administrator inbox from Amazon SNS, detailing the remediated security group, revoked permission payload, UTC timestamp, and remediation engine.
  9. *Documentation of Evidence Limitation:*
     The initial "before" screenshot (`17-a-rule-added.png`) was not captured prior to automated remediation. Because the auto-remediation workflow triggered and revoked the unauthorized rule in real time, the transient insecure state was already cleared before a manual browser capture could be obtained. The post-remediation security group state ([`17-b-rule-removed.png`](../screenshots/17-lambda/17-b-rule-removed.png)), CloudWatch execution logs ([`17-c-lambda-log.png`](../screenshots/17-lambda/17-c-lambda-log.png)), and real SNS email alert ([`17-d-sns-email.png`](../screenshots/17-lambda/17-d-sns-email.png)) confirm the operation of the control. In compliance with testing safety constraints, the dangerous rule was not re-authorized.
- **Expected Outcome:** Rogue rule removed automatically by Lambda, legitimate HTTP rule preserved, CloudWatch execution logs record successful revocation, and real SNS email notification delivered.
- **Actual Result:** The port 22 rule was automatically revoked in <60 seconds, port 80 from ALB remained intact, CloudWatch logs confirmed `REMEDIATION_SUCCESS`, and the SNS notification email was received.
- **Status:** **PASS (Automated Remediation Verified; Before Screenshot Omitted)**
- **Screenshots:**
  - [`17-b-rule-removed.png`](../screenshots/17-lambda/17-b-rule-removed.png) — EC2 Console showing `depi-sec-app-sg` post-remediation with port 22 removed and only port 80 from ALB remaining.
  - [`17-c-lambda-log.png`](../screenshots/17-lambda/17-c-lambda-log.png) — CloudWatch Logs stream displaying `REMEDIATION_TRIGGERED`, `REMEDIATION_SUCCESS`, and `SNS_ALERT_PUBLISHED`.
  - [`17-d-sns-email.png`](../screenshots/17-lambda/17-d-sns-email.png) — Real email notification received via Amazon SNS `depi-sec-alerts`.

---

### Test 8: Target Group Health Check, Automatic Failover & CloudWatch Alarm Verification
- **Objective:** Verify that the Application Load Balancer detects when an application instance becomes unhealthy, routes requests to the healthy instance, triggers CloudWatch Alarm `depi-sec-alb-unhealthy-hosts`, dispatches an automated SNS email notification, visualizes the failure on the `depi-sec-overview` operational dashboard, and recovers gracefully upon service restoration.
- **Empirical Evidence & Observed Procedure:**
  1. Connected to `depi-sec-app-a` (`i-0749711e008057ae1`) out-of-band via AWS Systems Manager Session Manager and stopped the web service:
     ```bash
     sudo systemctl stop nginx
     ```
  2. The ALB target health check detected consecutive health check failures and marked `depi-sec-app-a` as `Unhealthy` (`Health checks failed`) within ~90 seconds. Target `depi-sec-app-b` remained `Healthy`.
  3. Accessed the web application via CloudFront and ALB; verified that all incoming client requests seamlessly routed to `depi-sec-app-b` (`AZ: us-east-1b`) with zero user-facing service outage.
  4. CloudWatch metric `UnHealthyHostCount` rose from 0 to 1 on `depi-sec-tg` / `depi-sec-alb`.
  5. CloudWatch Alarm `depi-sec-alb-unhealthy-hosts` evaluated the breach (`Threshold Crossed: 1 datapoint [1.0 (15/10/26 23:01:00)] was greater than the threshold (0.0)`) and transitioned from `OK` to `ALARM` state at `2026-10-15 23:04:55 UTC`.
  6. Amazon SNS (`depi-sec-alerts`) published an automated notification email to subscriber `abouelyazeada@gmail.com`, detailing the alarm name, description, reason, timestamp, and affected resource ARNs.
  7. The CloudWatch operational dashboard `depi-sec-overview` reflected the incident in real-time on the `ALB Target Group UnHealthy Hosts` widget, showing the metric count rising from 0 to 1 against the threshold line.
  8. Restored the Nginx service on `depi-sec-app-a`:
     ```bash
     sudo systemctl start nginx
     ```
  9. The target group health checks returned `depi-sec-app-a` to `Healthy` status.
  10. Metric `UnHealthyHostCount` dropped back to 0, the alarm transitioned from `ALARM` back to `OK`, and the `depi-sec-overview` dashboard captured the complete failure-to-recovery curve.
  11. *Testing Boundary & Active Alarm Scope:* Alarms 1 (`depi-sec-ec2-cpu-high-app-a` and `app-b`), 3 (`depi-sec-rds-free-storage-low`), and 4 (`depi-sec-failed-console-logins-alarm`) were deployed with verified configurations and active `OK` state. In accordance with Task 16 specifications, only Alarm 2 (ALB Unhealthy Hosts) was actively triggered to validate the end-to-end alerting pipeline without generating synthetic CPU stress, filling database storage, or causing authentication lockouts.
- **Expected Outcome:** Unhealthy target bypassed, CloudWatch Alarm fires and sends SNS email notification, dashboard shows live metric anomaly, and target returns to Healthy upon restart.
- **Actual Result:**
  - ALB target group marked `app-a` Unhealthy while `app-b` served traffic.
  - Alarm `depi-sec-alb-unhealthy-hosts` entered `In alarm` state.
  - Real SNS alert email successfully delivered to `abouelyazeada@gmail.com`.
  - Operations dashboard `depi-sec-overview` displayed live telemetry spike to 1 and recovery to 0.
  - Both targets returned to Healthy upon service restart.
- **Status:** **PASS**
- **Screenshots:**
  - [`12-alb-unhealthy-target.png`](../screenshots/12-alb/12-alb-unhealthy-target.png) — Target Group console showing `app-a` marked `Unhealthy` and `app-b` marked `Healthy`.
  - [`12-alb-failover-working.png`](../screenshots/12-alb/12-alb-failover-working.png) — Browser displaying active response from `depi-sec-app-b`.
  - [`12-alb-recovered.png`](../screenshots/12-alb/12-alb-recovered.png) — Target Group console showing both targets in `Healthy` status.
  - [`16-alarm-unhealthy-hosts.png`](../screenshots/16-cloudwatch/16-alarm-unhealthy-hosts.png) — CloudWatch Alarms console showing `depi-sec-alb-unhealthy-hosts` in `In alarm` state and remaining alarms in `OK` state.
  - [`16-alarm-email-notification.png`](../screenshots/16-cloudwatch/16-alarm-email-notification.png) — Real email notification received via Amazon SNS `depi-sec-alerts`.
  - [`16-dashboard-overview.png`](../screenshots/16-cloudwatch/16-dashboard-overview.png) — Operational dashboard `depi-sec-overview` displaying all 4 widgets and the ALB unhealthy host count spike and recovery.

---

### Test 9: Inter-VPC Private Communication via Peering (Task 18)
- **Objective:** Verify private, bidirectional network routing and security group / NACL policy enforcement between Tools VPC (`10.1.0.0/16`) and App VPC (`10.0.0.0/16`) across same-account VPC Peering connection `pcx-066a78d3ee36e18f9` without crossing the public internet.
- **Empirical Evidence & Observed Procedure:**
  1. VPC Peering connection `depi-sec-app-tools-peering` (`pcx-066a78d3ee36e18f9`) was verified in the AWS Management Console with Status: `Active`, Requester: `depi-sec-app-vpc` (`10.0.0.0/16`), Accepter: `depi-sec-tools-vpc` (`10.1.0.0/16`).
  2. App private route table `depi-sec-private-rt` was inspected: route `10.1.0.0/16` targets `pcx-066a78d3ee36e18f9` with status `Active`.
  3. Tools route table `depi-sec-tools-rt` was inspected: route `10.0.0.0/16` targets `pcx-066a78d3ee36e18f9` with status `Active`.
  4. EC2 instance `depi-sec-tools-instance` (`i-039ddfc570cb61341`) was deployed in subnet `depi-sec-tools-a` (`10.1.1.0/24`) without a public IP address. AWS Systems Manager Session Manager verified connection status as `Online` via shared SSM Interface Endpoints in the App VPC.
  5. Initiated HTTP request from Tools instance (`10.1.1.0/24`) to App instance `depi-sec-app-a` private IP (`10.0.11.161`):
     ```bash
     curl -s -o /dev/null -w "%{http_code}" http://10.0.11.161
     ```
     The command returned HTTP status code `200` OK, confirming end-to-end packet flow across VPC peering, stateful SG evaluation, and stateless NACL evaluation.
  6. Initiated ICMP echo request from Tools instance to App instance using the exact verified command:
     ```bash
     ping -c 3 -W 3 10.0.11.161
     ```
     Result: 3 packets transmitted, 3 received, 0% packet loss, average RTT 0.225 ms.
  7. Executed direct external probe against the public ALB DNS without the custom CloudFront verification header:
     ```bash
     curl -s -o /dev/null -w "%{http_code}" http://depi-sec-alb-1246520704.us-east-1.elb.amazonaws.com
     ```
     The request returned HTTP status code `403` Forbidden, confirming perimeter origin header enforcement remains active and isolated from inter-VPC traffic.
- **Expected Outcome:** Tools instance connects privately to App instance returning HTTP 200 over VPC peering; direct external ALB access returns HTTP 403.
- **Actual Result:** Tools instance reached `10.0.11.161` with HTTP 200 OK and 0% ICMP packet loss; external ALB access returned HTTP 403 Forbidden.
- **Status:** **PASS**
- **Screenshots:**
  - [`18-peering-active.png`](../screenshots/18-peering/18-peering-active.png) — VPC Peering console showing `depi-sec-app-tools-peering` (`pcx-066a78d3ee36e18f9`) in `Active` status.
  - [`18-app-route-table.png`](../screenshots/18-peering/18-app-route-table.png) — Route table console showing `depi-sec-private-rt` with active route `10.1.0.0/16` targeting `pcx-066a78d3ee36e18f9`.
  - [`18-tools-route-table.png`](../screenshots/18-peering/18-tools-route-table.png) — Route table console showing `depi-sec-tools-rt` with active route `10.0.0.0/16` targeting `pcx-066a78d3ee36e18f9`.
  - [`18-peering-curl-success.png`](../screenshots/18-peering/18-peering-curl-success.png) — Terminal output showing HTTP 200 OK response from `10.0.11.161` and successful ICMP ping via peering.

---

## Pending Security Test Cases (Tasks 19–20)

The remaining test case from Task 20 requires components scheduled for subsequent project tasks:

- **Test 10: AWS Backup Vault Lock Immutability (Task 19)**
  - *Procedure:* Attempt to delete a backup recovery point inside the locked vault using root/admin credentials.
  - *Expected Result:* AWS Backup rejects the deletion with `AccessDeniedException` due to Vault Lock policy.
  - *Status:* **Pending Task 19 implementation.**
