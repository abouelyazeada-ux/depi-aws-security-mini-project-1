"""
Task 17: Event-Driven Security Auto-Remediation (Lambda & EventBridge)

Automated remediation function that inspects EC2 security group ingress authorization
events from AWS CloudTrail via Amazon EventBridge. If an inbound IPv4 rule allows
0.0.0.0/0 on TCP port 22 (SSH) or port 3389 (RDP) - including port ranges that cover
either port or all-traffic rules (-1) - the function automatically revokes the offending
public CIDR permission while preserving legitimate rules and CIDRs, emits structured
CloudWatch logs, and dispatches an alert to Amazon SNS.
"""

import datetime
import json
import logging
import os
import re
import boto3
from botocore.exceptions import ClientError

# Configure structured logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients outside handler for connection reuse
ec2 = boto3.client("ec2")
sns = boto3.client("sns")

# Configuration constants & environment variables
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
TARGET_SECURITY_GROUP_ID = os.environ.get("TARGET_SECURITY_GROUP_ID")
DANGEROUS_PORTS = (22, 3389)
DANGEROUS_CIDR = "0.0.0.0/0"
SG_ID_REGEX = re.compile(r"^sg-[0-9a-fA-F]{8,17}$")


def validate_event_envelope(event):
    """
    Validates that the incoming event matches the expected EventBridge envelope
    for a successful CloudTrail AuthorizeSecurityGroupIngress EC2 API call.
    Returns (is_valid: bool, reason: str, is_failed_api_call: bool).
    """
    if not isinstance(event, dict):
        return False, "EVENT_NOT_DICT", False

    if event.get("source") != "aws.ec2":
        return False, f"UNEXPECTED_SOURCE: {event.get('source')}", False

    if event.get("detail-type") != "AWS API Call via CloudTrail":
        return False, f"UNEXPECTED_DETAIL_TYPE: {event.get('detail-type')}", False

    detail = event.get("detail")
    if not isinstance(detail, dict):
        return False, "DETAIL_NOT_DICT", False

    if detail.get("eventSource") != "ec2.amazonaws.com":
        return False, f"UNEXPECTED_EVENT_SOURCE: {detail.get('eventSource')}", False

    if detail.get("eventName") != "AuthorizeSecurityGroupIngress":
        return False, f"UNEXPECTED_EVENT_NAME: {detail.get('eventName')}", False

    # Ignore failed API calls where CloudTrail recorded an error (no rules were applied)
    if "errorCode" in detail or "errorMessage" in detail:
        error_code = detail.get("errorCode", "UnknownError")
        return False, f"API_CALL_FAILED_IN_CLOUDTRAIL: {error_code}", True

    return True, "VALID", False


def extract_security_group_id(event):
    """
    Safely extract and validate the Security Group ID from CloudTrail EventBridge event.
    Handles multiple variations in CloudTrail requestParameters and responseElements.
    """
    detail = event.get("detail")
    if not isinstance(detail, dict):
        return None

    request_params = detail.get("requestParameters")
    if isinstance(request_params, dict):
        # Primary VPC security group parameter
        group_id = request_params.get("groupId")
        if group_id and isinstance(group_id, str) and SG_ID_REGEX.match(group_id):
            return group_id

        # Secondary: groupIdSet if batch or API variant
        group_id_set = request_params.get("groupIdSet")
        if isinstance(group_id_set, dict):
            items = group_id_set.get("items")
            if isinstance(items, list) and items and isinstance(items[0], dict):
                candidate = items[0].get("groupId")
                if candidate and isinstance(candidate, str) and SG_ID_REGEX.match(candidate):
                    return candidate

    # Fallback to responseElements if present
    response_elements = detail.get("responseElements")
    if isinstance(response_elements, dict):
        candidate = response_elements.get("groupId")
        if candidate and isinstance(candidate, str) and SG_ID_REGEX.match(candidate):
            return candidate

    return None


def is_permission_dangerous(rule):
    """
    Evaluates whether an IpPermission item permits 0.0.0.0/0 on port 22 or 3389,
    including discrete ports, overlapping port ranges, or all-traffic rules (-1).
    """
    proto = str(rule.get("IpProtocol", "")).lower()
    from_port = rule.get("FromPort")
    to_port = rule.get("ToPort")

    # Check if 0.0.0.0/0 is present in the IPv4 ranges
    ip_ranges = rule.get("IpRanges", [])
    has_public_cidr = any(r.get("CidrIp") == DANGEROUS_CIDR for r in ip_ranges if isinstance(r, dict))
    if not has_public_cidr:
        return False

    # Protocol -1 exposes all ports (including 22 and 3389) to 0.0.0.0/0
    if proto == "-1":
        return True

    # Check TCP protocol port ranges
    if proto == "tcp":
        if from_port is not None and to_port is not None:
            # Overlapping port ranges covering port 22 or 3389
            if any(from_port <= dp <= to_port for dp in DANGEROUS_PORTS):
                return True

    return False


def build_revocation_item(rule):
    """
    Builds a precise IpPermissions item to revoke ONLY the 0.0.0.0/0 CIDR,
    preserving all other CIDRs, prefix lists, and security group references.
    """
    revoke_item = {
        "IpProtocol": rule["IpProtocol"],
        "IpRanges": [{"CidrIp": DANGEROUS_CIDR}]
    }
    if "FromPort" in rule and rule["FromPort"] is not None:
        revoke_item["FromPort"] = rule["FromPort"]
    if "ToPort" in rule and rule["ToPort"] is not None:
        revoke_item["ToPort"] = rule["ToPort"]

    return revoke_item


def publish_sns_alert(group_id, revoked_rules):
    """
    Publishes a structured security alert to Amazon SNS.
    Returns (sns_publish_status: str, message_id_or_error: str).
    Note: A successful publish confirms acceptance by Amazon SNS topic;
    downstream subscriber email delivery is handled asynchronously.
    """
    if not SNS_TOPIC_ARN:
        logger.warning(json.dumps({
            "action": "SNS_PUBLISH_SKIPPED",
            "reason": "SNS_TOPIC_ARN environment variable not configured",
            "security_group_id": group_id
        }))
        return "SKIPPED_NO_TOPIC", "SNS_TOPIC_ARN_NOT_CONFIGURED"

    subject = f"[AUTO-REMEDIATION] Revoked open ingress on {group_id}"[:100]
    timestamp_utc = datetime.datetime.now(datetime.timezone.utc).isoformat()
    region = os.environ.get("AWS_REGION", "us-east-1")

    message_lines = [
        "SECURITY AUTO-REMEDIATION REPORT",
        "=================================",
        "Event: Unauthorized Ingress Rule Revoked",
        f"Timestamp (UTC): {timestamp_utc}",
        f"AWS Region: {region}",
        f"Security Group ID: {group_id}",
        "",
        "Detection Rationale:",
        f"Inbound rule permitting unrestricted public access ({DANGEROUS_CIDR}) on sensitive",
        f"administrative port(s) {list(DANGEROUS_PORTS)} was authorized.",
        "",
        "Action Taken:",
        "Offending 0.0.0.0/0 ingress rule was automatically revoked by AWS Lambda.",
        "Legitimate rules and authorized internal CIDR ranges remain intact.",
        "",
        "Revoked Permission Details:",
        json.dumps(revoked_rules, indent=2),
        "",
        "Remediation Engine:",
        "AWS Lambda (depi-sec-auto-remediation) triggered via Amazon EventBridge & AWS CloudTrail.",
        "",
        "Delivery Notice:",
        "This notification confirms successful publication to the Amazon SNS topic.",
        "Downstream email delivery to subscribers is processed asynchronously by Amazon SNS."
    ]
    message_body = "\n".join(message_lines)

    try:
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message_body
        )
        message_id = response.get("MessageId", "Unknown")
        logger.info(json.dumps({
            "action": "SNS_ALERT_PUBLISHED",
            "topic_arn": SNS_TOPIC_ARN,
            "security_group_id": group_id,
            "sns_message_id": message_id,
            "delivery_note": "Published to topic; email delivery handled asynchronously by Amazon SNS"
        }))
        return "PUBLISHED_TO_TOPIC", message_id
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        error_msg = e.response.get("Error", {}).get("Message", str(e))
        logger.error(json.dumps({
            "action": "SNS_PUBLISH_FAILED",
            "topic_arn": SNS_TOPIC_ARN,
            "security_group_id": group_id,
            "error_code": error_code,
            "error_message": error_msg
        }))
        return "SNS_PUBLISH_FAILED", error_code


def lambda_handler(event, context):
    """
    Main Lambda handler invoked by Amazon EventBridge on AuthorizeSecurityGroupIngress.
    """
    # 1. Validate incoming EventBridge envelope
    is_valid, validation_reason, is_failed_api_call = validate_event_envelope(event)
    if not is_valid:
        logger.info(json.dumps({
            "action": "EVENT_VALIDATION_SKIPPED",
            "reason": validation_reason,
            "is_failed_api_call": is_failed_api_call
        }))
        return {
            "remediation_status": "SKIPPED_INVALID_OR_FAILED_EVENT",
            "reason": validation_reason
        }

    logger.info(json.dumps({
        "action": "EVENT_RECEIVED",
        "detail_type": event.get("detail-type"),
        "source": event.get("source"),
        "event_name": event.get("detail", {}).get("eventName"),
        "aws_region": event.get("detail", {}).get("awsRegion")
    }))

    # 2. Extract and validate Security Group ID
    group_id = extract_security_group_id(event)
    if not group_id:
        logger.warning(json.dumps({
            "action": "EXTRACTION_FAILED",
            "message": "No valid Security Group ID found in event detail. Exiting safely.",
            "event_detail_keys": list(event.get("detail", {}).keys()) if isinstance(event.get("detail"), dict) else []
        }))
        return {
            "remediation_status": "SKIPPED_NO_VALID_GROUP_ID"
        }

    # 3. Check scope against TARGET_SECURITY_GROUP_ID if configured
    if TARGET_SECURITY_GROUP_ID and group_id != TARGET_SECURITY_GROUP_ID:
        logger.info(json.dumps({
            "action": "SCOPE_CHECK_SKIPPED",
            "inspected_group_id": group_id,
            "target_group_id": TARGET_SECURITY_GROUP_ID,
            "message": "Security group does not match configured target. Skipping remediation."
        }))
        return {
            "remediation_status": "SKIPPED_OUT_OF_SCOPE",
            "security_group_id": group_id
        }

    # 4. Query current rules from EC2
    try:
        response = ec2.describe_security_groups(GroupIds=[group_id])
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        error_msg = e.response.get("Error", {}).get("Message", str(e))
        logger.error(json.dumps({
            "action": "DESCRIBE_FAILED",
            "security_group_id": group_id,
            "error_code": error_code,
            "error_message": error_msg
        }))
        return {
            "remediation_status": "ERROR_DESCRIBE",
            "security_group_id": group_id,
            "error": error_code
        }

    security_groups = response.get("SecurityGroups", [])
    if not security_groups:
        logger.warning(json.dumps({
            "action": "GROUP_NOT_FOUND",
            "security_group_id": group_id,
            "message": "Security group does not exist in describe response."
        }))
        return {
            "remediation_status": "GROUP_NOT_FOUND",
            "security_group_id": group_id
        }

    sg = security_groups[0]
    current_permissions = sg.get("IpPermissions", [])

    logger.info(json.dumps({
        "action": "SECURITY_GROUP_INSPECTED",
        "security_group_id": group_id,
        "security_group_name": sg.get("GroupName"),
        "total_rules_inspected": len(current_permissions)
    }))

    # 5. Identify offending permissions
    permissions_to_revoke = []
    for rule in current_permissions:
        if is_permission_dangerous(rule):
            permissions_to_revoke.append(build_revocation_item(rule))

    if not permissions_to_revoke:
        logger.info(json.dumps({
            "action": "INSPECTION_CLEAN",
            "security_group_id": group_id,
            "message": "No unauthorized 0.0.0.0/0 rules on restricted ports detected."
        }))
        return {
            "remediation_status": "CLEAN",
            "security_group_id": group_id,
            "sns_publish_status": "SKIPPED_NOT_NEEDED"
        }

    # 6. Revoke offending permissions
    logger.warning(json.dumps({
        "action": "REMEDIATION_TRIGGERED",
        "security_group_id": group_id,
        "offending_rules_count": len(permissions_to_revoke),
        "rules_to_revoke": permissions_to_revoke
    }))

    try:
        ec2.revoke_security_group_ingress(
            GroupId=group_id,
            IpPermissions=permissions_to_revoke
        )
        logger.info(json.dumps({
            "action": "REMEDIATION_SUCCESS",
            "security_group_id": group_id,
            "revoked_rules_count": len(permissions_to_revoke),
            "revoked_rules": permissions_to_revoke
        }))
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        error_msg = e.response.get("Error", {}).get("Message", str(e))

        # Handle duplicate event / concurrent execution / race condition
        if error_code == "InvalidPermission.NotFound":
            logger.warning(json.dumps({
                "action": "CONFLICT_DETECTED",
                "security_group_id": group_id,
                "error_code": error_code,
                "message": "Revocation encountered InvalidPermission.NotFound; reinspecting active ingress rules to confirm security posture."
            }))

            # Re-describe security group to verify active state
            try:
                recheck_resp = ec2.describe_security_groups(GroupIds=[group_id])
                recheck_sgs = recheck_resp.get("SecurityGroups", [])
                recheck_rules = recheck_sgs[0].get("IpPermissions", []) if recheck_sgs else []
            except ClientError as describe_err:
                recheck_err_code = describe_err.response.get("Error", {}).get("Code", "Unknown")
                logger.error(json.dumps({
                    "action": "REINSPECT_FAILED",
                    "security_group_id": group_id,
                    "error_code": recheck_err_code
                }))
                return {
                    "remediation_status": "ERROR_REINSPECT",
                    "security_group_id": group_id,
                    "error": recheck_err_code
                }

            remaining_dangerous = [r for r in recheck_rules if is_permission_dangerous(r)]
            if remaining_dangerous:
                # Dangerous rules still exist; remediation did NOT succeed
                logger.error(json.dumps({
                    "action": "REMEDIATION_INCOMPLETE",
                    "security_group_id": group_id,
                    "remaining_dangerous_count": len(remaining_dangerous),
                    "message": "Dangerous ingress rules remain active after failed revocation attempt."
                }))
                return {
                    "remediation_status": "FAILED_DANGEROUS_RULES_REMAIN",
                    "security_group_id": group_id,
                    "remaining_dangerous_count": len(remaining_dangerous),
                    "sns_publish_status": "SKIPPED_FAILED_REMEDIATION"
                }

            # Security group is verified clean; concurrent execution already remediated the rule
            logger.info(json.dumps({
                "action": "ALREADY_CLEAN_VERIFIED",
                "security_group_id": group_id,
                "message": "Security group reinspected: no unauthorized open rules remain (concurrently remediated). Skipping redundant alert."
            }))
            return {
                "remediation_status": "ALREADY_CLEAN",
                "security_group_id": group_id,
                "sns_publish_status": "SKIPPED_NOT_NEEDED"
            }

        logger.error(json.dumps({
            "action": "REVOCATION_FAILED",
            "security_group_id": group_id,
            "error_code": error_code,
            "error_message": error_msg
        }))
        return {
            "remediation_status": "ERROR_REVOCATION",
            "security_group_id": group_id,
            "error": error_code
        }

    # 7. Publish SNS notification
    sns_publish_status, sns_detail = publish_sns_alert(group_id, permissions_to_revoke)

    return {
        "remediation_status": "REMEDIATED",
        "security_group_id": group_id,
        "revoked_rules_count": len(permissions_to_revoke),
        "sns_publish_status": sns_publish_status,
        "sns_detail": sns_detail
    }
