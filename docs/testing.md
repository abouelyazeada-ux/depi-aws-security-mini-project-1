# Security Testing & Verification Report — Tasks 1–13

This document records the empirical validation of the security controls implemented in **Tasks 1–13**, following the standardized test framework outlined in **Task 20** of `Project-1.pdf`.

Each test case details the operational procedure performed, the expected security outcome, the observed real-world behavior, and links to the supporting screenshot evidence. Tests are strictly documented based on confirmed evidence without assuming or inferring unexecuted steps. Tests associated with **Tasks 14–20** that require pending infrastructure are explicitly identified as **Pending Implementation**.

---

## Test Execution Summary Matrix

| # | Test Case Description | Target Component | Expected Result | Actual Outcome | Status | Evidence Link |
| :-: | :--- | :--- | :--- | :--- | :-: | :--- |
| **1** | Open ALB DNS name directly in browser / CLI | Application Load Balancer (`depi-sec-alb`) | HTTP `403 Forbidden` | Returned HTTP 403 status code and body `"Access Denied"` | **PASS** | [`13-cloudfront-alb-denied.png`](../screenshots/13-cloudfront/13-cloudfront-alb-denied.png)<br>[`13-cloudfront-403-status.png`](../screenshots/13-cloudfront/13-cloudfront-403-status.png) |
| **2** | Open CloudFront distribution URL | AWS CloudFront (`depi-sec-cloudfront`) | Page loads over HTTPS | Loaded `https://dfj4o8x4memfi.cloudfront.net` displaying backend page | **PASS** | [`13-cloudfront-https-working.png`](../screenshots/13-cloudfront/13-cloudfront-https-working.png) |
| **3** | Direct SSH attempt to private EC2 instance | EC2 Application Tier (`depi-sec-app-a/b`) | Timeout / Unreachable | Instances have no public IPs; NACL denies port 22; direct SSH command **not executed** | **PARTIAL** | [`08-ec2-app-a-no-public-ip.png`](../screenshots/08-session-manager/08-ec2-app-a-no-public-ip.png)<br>[`08-ec2-app-b-no-public-ip.png`](../screenshots/08-session-manager/08-ec2-app-b-no-public-ip.png)<br>[`06-nacl-inbound-rules.png`](../screenshots/06-nacl/06-nacl-inbound-rules.png) |
| **4** | Direct connection to RDS from external client | Amazon RDS MySQL (`depi-sec-db`) | Connection fails / timeout | PowerShell `Test-NetConnection` to port 3306 failed (`TcpTestSucceeded : False`) | **PASS** | [`11-rds-external-connection-failed.png`](../screenshots/11-rds/11-rds-external-connection-failed.png)<br>[`11-rds-private-access.png`](../screenshots/11-rds/11-rds-private-access.png) |
| **5** | TCP connection to RDS from internal EC2 instance | Amazon RDS MySQL (`depi-sec-db`) | Port 3306 reachable | Bash `/dev/tcp` probe confirmed: `SUCCESS: RDS port 3306 is reachable` | **PASS (Network Reachability)** | [`11-rds-internal-connection.png`](../screenshots/11-rds/11-rds-internal-connection.png) |
| **6** | Anonymous / public access to S3 test object | Amazon S3 (`depi-sec-app-*`) | Access denied / refused | Unauthenticated `curl -I` returned `HTTP/1.1 403 Forbidden`; explicit ACL mutation **not executed** | **PASS (Anonymous Read Refusal) / PARTIAL** | [`10-s3-public-access-refused.png`](../screenshots/10-s3/10-s3-public-access-refused.png)<br>[`10-app-bucket-public-access-block.png`](../screenshots/10-s3/10-app-bucket-public-access-block.png) |
| **7** | Add SSH rule (`0.0.0.0/0:22`) to App SG | Security Auto-Remediation | Removed by Lambda in <60s | *Pending Task 17 Lambda deployment* | **PENDING** | *Awaiting Task 17* |
| **8** | Stop Nginx web service on one instance | ALB Target Group (`depi-sec-tg`) | Target marked Unhealthy; traffic routes to healthy target | `app-a` marked Unhealthy in console; traffic served by `app-b`; returned to Healthy | **PASS** | [`12-alb-unhealthy-target.png`](../screenshots/12-alb/12-alb-unhealthy-target.png)<br>[`12-alb-failover-working.png`](../screenshots/12-alb/12-alb-failover-working.png)<br>[`12-alb-recovered.png`](../screenshots/12-alb/12-alb-recovered.png) |
| **9** | Curl app server from peering tools VPC | VPC Peering Connection | HTTP 200 via private route | *Pending Task 18 Peering deployment* | **PENDING** | *Awaiting Task 18* |
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
- **Objective:** Confirm whether the private EC2 instances have public IP addresses and whether the network ACL restricts inbound SSH traffic.
- **Empirical Evidence & Observed Procedure:**
  1. EC2 instance configuration was inspected in the AWS Management Console:
     - Instance `depi-sec-app-a` (`i-0749711e008057ae1`): Public IPv4 address is empty (`-`). Private IP is `10.0.11.109`.
     - Instance `depi-sec-app-b` (`i-0306fb121beae9963`): Public IPv4 address is empty (`-`). Private IP is `10.0.12.82`.
  2. Network ACL `depi-sec-private-nacl` configuration was inspected in the AWS Console:
     - Inbound Rule 200 explicitly sets: Protocol: `TCP (6)`, Port range: `22`, Source: `0.0.0.0/0`, Allow/Deny: `DENY`.
  3. *Execution Status Note:* An active `ssh` command-line connection attempt from an external client was **NOT EXECUTED** in the recorded evidence.
- **Expected Outcome:** Instances cannot be reached via direct internet SSH due to absence of public IPs and explicit NACL drop.
- **Actual Result:** Confirmed from console configurations that neither instance has a public IP address and that inbound port 22 is explicitly denied by the private NACL. Direct SSH execution remains unexecuted, and full Flow Log `REJECT` verification is pending Task 15.
- **Status:** **PARTIAL**
- **Screenshots:**
  - [`08-ec2-app-a-no-public-ip.png`](../screenshots/08-session-manager/08-ec2-app-a-no-public-ip.png) — AWS Console showing `depi-sec-app-a` with no public IPv4 address (`-`).
  - [`08-ec2-app-b-no-public-ip.png`](../screenshots/08-session-manager/08-ec2-app-b-no-public-ip.png) — AWS Console showing `depi-sec-app-b` with no public IPv4 address (`-`).
  - [`06-nacl-inbound-rules.png`](../screenshots/06-nacl/06-nacl-inbound-rules.png) — AWS Console showing `depi-sec-private-nacl` Inbound Rule 200 DENY TCP 22.

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

### Test 8: Target Group Health Check & Automatic Failover
- **Objective:** Verify that the Application Load Balancer detects when an application instance becomes unhealthy and routes requests to the healthy instance.
- **Empirical Evidence & Observed Procedure:**
  1. Inspected Target Group `depi-sec-tg` in the AWS Management Console:
     - `depi-sec-app-b` (`i-0306fb121beae9963` / `us-east-1b`): `Healthy`
     - `depi-sec-app-a` (`i-0749711e008057ae1` / `us-east-1a`): `Unhealthy` (`Health checks failed`)
  2. Accessed the web application through the ALB URL in a browser while `app-a` was unhealthy.
  3. Inspected Target Group `depi-sec-tg` after service recovery.
- **Expected Outcome:** Traffic is directed to the healthy target while the unhealthy target is bypassed; targets recover to Healthy when operational.
- **Actual Result:**
  - The AWS Console confirmed `depi-sec-tg` registered 1 Healthy target (`app-b`) and 1 Unhealthy target (`app-a`).
  - Web requests routed to `depi-sec-app-b` (`AZ: us-east-1b`).
  - Upon service recovery, Target Group console confirmed both targets returned to `Healthy` status.
  - *Note on Scope:* Exact failover timestamps or packet drop measurements were not recorded and are not claimed.
- **Status:** **PASS**
- **Screenshots:**
  - [`12-alb-unhealthy-target.png`](../screenshots/12-alb/12-alb-unhealthy-target.png) — Target Group console showing `app-a` marked `Unhealthy` and `app-b` marked `Healthy`.
  - [`12-alb-failover-working.png`](../screenshots/12-alb/12-alb-failover-working.png) — Browser displaying active response from `depi-sec-app-b`.
  - [`12-alb-recovered.png`](../screenshots/12-alb/12-alb-recovered.png) — Target Group console showing both targets in `Healthy` status.

---

## Pending Security Test Cases (Tasks 14–20)

The remaining test cases from Task 20 require components scheduled for subsequent project tasks:

- **Test 7: Security Group Auto-Remediation (Task 17)**
  - *Procedure:* Add rule `0.0.0.0/0:22` to `depi-sec-app-sg`.
  - *Expected Result:* EventBridge triggers a Lambda function that removes the rogue rule and publishes an alert to SNS.
  - *Status:* **Pending Task 17 implementation.**
- **Test 9: Inter-VPC Private Communication via Peering (Task 18)**
  - *Procedure:* From an administrative instance in the Tools VPC, curl the private IP of an application server across the peering connection.
  - *Expected Result:* HTTP 200 returned over private route without transit across the public internet.
  - *Status:* **Pending Task 18 implementation.**
- **Test 10: AWS Backup Vault Lock Immutability (Task 19)**
  - *Procedure:* Attempt to delete a backup recovery point inside the locked vault using root/admin credentials.
  - *Expected Result:* AWS Backup rejects the deletion with `AccessDeniedException` due to Vault Lock policy.
  - *Status:* **Pending Task 19 implementation.**
