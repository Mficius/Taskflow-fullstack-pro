package main

import rego.v1

rds_ok := {"address": "aws_db_instance.main", "type": "aws_db_instance", "change": {"actions": ["create"], "after": {"publicly_accessible": false, "storage_encrypted": true, "backup_retention_period": 7}}}

test_rds_ok if {
	count(deny) == 0 with input as {"resource_changes": [rds_ok]}
}

test_rds_public_denied if {
	bad := {"address": "aws_db_instance.main", "type": "aws_db_instance", "change": {"actions": ["create"], "after": {"publicly_accessible": true, "storage_encrypted": true, "backup_retention_period": 7}}}
	count(deny) > 0 with input as {"resource_changes": [bad]}
}

test_ssh_open_denied if {
	bad := {"address": "aws_vpc_security_group_ingress_rule.ssh", "type": "aws_vpc_security_group_ingress_rule", "change": {"actions": ["create"], "after": {"cidr_ipv4": "0.0.0.0/0", "from_port": 22}}}
	count(deny) > 0 with input as {"resource_changes": [bad]}
}

test_https_open_allowed if {
	ok := {"address": "aws_vpc_security_group_ingress_rule.https", "type": "aws_vpc_security_group_ingress_rule", "change": {"actions": ["create"], "after": {"cidr_ipv4": "0.0.0.0/0", "from_port": 443}}}
	count(deny) == 0 with input as {"resource_changes": [ok]}
}

test_star_policy_denied if {
	pol := json.marshal({"Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}]})
	bad := {"address": "aws_iam_role_policy.x", "type": "aws_iam_role_policy", "change": {"actions": ["create"], "after": {"policy": pol}}}
	count(deny) > 0 with input as {"resource_changes": [bad]}
}

test_github_oidc_without_sub_denied if {
	trust := json.marshal({"Statement": [{"Effect": "Allow", "Principal": {"Federated": "arn:aws:iam::1:oidc-provider/token.actions.githubusercontent.com"}, "Condition": {"StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"}}}]})
	bad := {"address": "aws_iam_role.gh", "type": "aws_iam_role", "change": {"actions": ["create"], "after": {"assume_role_policy": trust}}}
	count(deny) > 0 with input as {"resource_changes": [bad]}
}

test_github_oidc_with_sub_ok if {
	trust := json.marshal({"Statement": [{"Effect": "Allow", "Principal": {"Federated": "arn:aws:iam::1:oidc-provider/token.actions.githubusercontent.com"}, "Condition": {"StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com", "token.actions.githubusercontent.com:sub": "repo:o/r:environment:production"}}}]})
	ok := {"address": "aws_iam_role.gh", "type": "aws_iam_role", "change": {"actions": ["create"], "after": {"assume_role_policy": trust}}}
	count(deny) == 0 with input as {"resource_changes": [ok]}
}
