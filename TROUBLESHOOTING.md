# Troubleshooting - Project Bedrock

This covers how to check on the system, debug common failures, and recover from broken states.

---

## Getting Access

```bash
aws eks update-kubeconfig --name project-bedrock-cluster --region us-east-1
kubectl get nodes
kubectl get pods -n retail-app
```

---

## Health Checks

**Nodes:**

```bash
kubectl get nodes
kubectl top nodes
```

**App pods:**

```bash
kubectl get pods -n retail-app
kubectl get pods -n kube-system | grep -E 'aws-load-balancer|external-secrets'
```

All pods should be `Running` with restarts near zero.

**Secrets sync:**

```bash
kubectl get externalsecret -n retail-app
```

Both `catalog-db` and `orders-db` should show `SecretSynced`. If either shows an error, see the secret sync section below.

**Ingress:**

```bash
kubectl get ingress retail-ui -n retail-app
kubectl describe ingress retail-ui -n retail-app
```

The ADDRESS field should populate within about 3 minutes of the ingress being created. If it stays empty after 5 minutes, something is wrong with the Load Balancer Controller.

---

## Viewing Logs

```bash
kubectl logs -n retail-app deployment/ui --tail=100
kubectl logs -n retail-app deployment/catalog --tail=100
kubectl logs -n retail-app deployment/orders --tail=100
kubectl logs -n retail-app deployment/carts --tail=100
kubectl logs -n retail-app deployment/checkout --tail=100
```

Add `-f` to follow. Use `--previous` to see logs from a crashed container.

Logs also end up in CloudWatch Container Insights under `/aws/containerinsights/project-bedrock-cluster/`.

---

## Pod Restarts and CrashLoopBackOff

Start with:

```bash
kubectl describe pod -n retail-app <pod-name>
kubectl logs -n retail-app <pod-name> --previous
```

The most common causes by service:

**catalog or orders:** The secret probably hasn't synced yet. Check `kubectl get externalsecret -n retail-app`. Also verify the RDS endpoint in [helm/values.yaml](helm/values.yaml) actually matches what Terraform provisioned - run `terraform output mysql_address` and `terraform output postgres_address` to confirm.

**carts:** Usually an IRSA problem. Check `kubectl get sa carts -n retail-app -o yaml` and make sure the `eks.amazonaws.com/role-arn` annotation matches `terraform output carts_role_arn`.

**OOMKilled:** The pod hit the 512Mi memory limit. Check `kubectl top pods -n retail-app` to see current usage.

---

## Secret Sync Failures

If `kubectl get externalsecret -n retail-app` shows `SecretSyncedError`, describe the failing resource:

```bash
kubectl describe externalsecret catalog-db -n retail-app
kubectl describe externalsecret orders-db -n retail-app
```

The most likely cause is a bad IRSA annotation on the `external-secrets-sa` service account. Check it:

```bash
kubectl get sa external-secrets-sa -n retail-app -o yaml
```

The `eks.amazonaws.com/role-arn` annotation should match:

```bash
cd terraform && terraform output eso_role_arn
```

If it's wrong or missing, patch it and restart ESO:

```bash
kubectl annotate sa external-secrets-sa -n retail-app \
  eks.amazonaws.com/role-arn=<arn> --overwrite
kubectl rollout restart deployment -n external-secrets
```

---

## ALB Not Provisioning

If the ingress ADDRESS is still empty after 5 minutes, check the Load Balancer Controller logs:

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=100
```

Then check its service account annotation:

```bash
kubectl get sa aws-load-balancer-controller -n kube-system -o yaml
```

The `eks.amazonaws.com/role-arn` should match:

```bash
cd terraform && terraform output lb_controller_role_arn
```

Patch and restart if needed:

```bash
kubectl annotate sa aws-load-balancer-controller -n kube-system \
  eks.amazonaws.com/role-arn=<arn> --overwrite
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

---

## DynamoDB Access Errors (Carts)

If carts pods are logging `AccessDeniedException`, the service account annotation is wrong. Check it:

```bash
kubectl get sa carts -n retail-app -o yaml
```

Get the expected ARN:

```bash
cd terraform && terraform output carts_role_arn
```

Patch and redeploy:

```bash
kubectl annotate sa carts -n retail-app \
  eks.amazonaws.com/role-arn=<arn> --overwrite
kubectl rollout restart deployment/carts -n retail-app
```

---

## RDS Connectivity Issues

RDS is private and only reachable from the EKS nodes. To test from inside the cluster:

```bash
kubectl exec -n retail-app -it deployment/catalog -- sh
# then inside:
nc -zv project-bedrock-catalog.c810uy8ocbmj.us-east-1.rds.amazonaws.com 3306
```

If the connection times out, either the security group rules are wrong or the endpoint in [helm/values.yaml](helm/values.yaml) is stale. Verify against Terraform:

```bash
cd terraform
terraform output mysql_address
terraform output postgres_address
```

If the endpoints differ, update [helm/values.yaml](helm/values.yaml) and redeploy:

```bash
helm upgrade retail-store ./helm --namespace retail-app --wait
```

---

## Redeploying a Service

To force a rollout (useful after a secret rotation or config change):

```bash
kubectl rollout restart deployment/<service-name> -n retail-app
kubectl rollout status deployment/<service-name> -n retail-app
```

To redeploy everything:

```bash
helm upgrade retail-store ./helm --namespace retail-app --wait
kubectl apply -f k8s/ingress.yaml
```

---

## Scaling Nodes

The node group will auto-scale between 2 and 3 nodes. To manually change the range or desired count via CLI:

```bash
aws eks update-nodegroup-config \
  --cluster-name project-bedrock-cluster \
  --nodegroup-name project-bedrock-ng \
  --scaling-config minSize=2,maxSize=4,desiredSize=3
```

Or update the values in [terraform/eks.tf](terraform/eks.tf) and apply through Terraform.

---

## GitHub Actions Failures

View recent runs:

```bash
gh run list --repo alexindevs/project-bedrock --limit 10
gh run view <run-id> --repo alexindevs/project-bedrock --log
```

If the workflow is failing on AWS auth, confirm the `AWS_ROLE_ARN` secret is set:

```bash
gh secret list --repo alexindevs/project-bedrock
```

Reset it if needed:

```bash
gh secret set AWS_ROLE_ARN \
  --body "$(cd terraform && terraform output -raw github_actions_role_arn)" \
  --repo alexindevs/project-bedrock
```

---

## Lambda Asset Processor

Check recent invocations:

```bash
aws logs tail /aws/lambda/bedrock-asset-processor --since 1h --region us-east-1
```

Test it manually:

```bash
aws lambda invoke \
  --function-name bedrock-asset-processor \
  --region us-east-1 \
  --payload '{"Records":[{"s3":{"object":{"key":"test/image.jpg"}}}]}' \
  /tmp/lambda-out.json && cat /tmp/lambda-out.json
```

---

## Tear Down

```bash
cd terraform
terraform destroy
```

RDS and EKS take around 10-15 minutes each. NAT Gateways take about 5 minutes. The S3 tfstate bucket (`bedrock-tfstate-alt-soe-025-5437`) is not managed by Terraform, so delete it manually if you're fully decommissioning.
