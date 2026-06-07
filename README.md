# Project Bedrock

EKS capstone deployment for InnovateMart Inc. AWS Retail Store Sample App on Amazon EKS with managed data services.

| Component | Technology |
|-----------|-----------|
| Compute | EKS 1.34, managed node group (AL2023) |
| Catalog DB | RDS MySQL 8.0 |
| Orders DB | RDS PostgreSQL 16 |
| Carts | DynamoDB (PAY_PER_REQUEST) |
| Secrets | AWS Secrets Manager + External Secrets Operator |
| Ingress | AWS Load Balancer Controller (ALB) |
| Observability | CloudWatch Container Insights |
| Asset pipeline | S3 + Lambda |
| CI/CD | GitHub Actions (OIDC, no static keys) |

---

## Deployment Sequence

### 1. Bootstrap Remote State

The S3 backend bucket must exist before `terraform init` can run. Create it once:

```bash
aws s3api create-bucket \
  --bucket bedrock-tfstate-alt-soe-025-5437 \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket bedrock-tfstate-alt-soe-025-5437 \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket bedrock-tfstate-alt-soe-025-5437 \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket bedrock-tfstate-alt-soe-025-5437 \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### 2. Terraform (Core Infrastructure)

```bash
cd terraform
terraform init
terraform apply
```

Update kubeconfig:
```bash
aws eks update-kubeconfig \
  --name project-bedrock-cluster \
  --region us-east-1
```

### 3. AWS Load Balancer Controller

Apply the service account (IRSA annotation already set):
```bash
kubectl apply -f k8s/lb-controller/sa.yaml
```

Install the controller via Helm:
```bash
VPC_ID=$(cd terraform && terraform output -raw vpc_id)

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=project-bedrock-cluster \
  --set region=us-east-1 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set vpcId=$VPC_ID \
  --wait
```

Verify:
```bash
kubectl rollout status deployment aws-load-balancer-controller -n kube-system
```

### 4. External Secrets Operator

Install ESO:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --set installCRDs=true \
  --wait
```

Apply the ESO service account, SecretStore, and ExternalSecrets:
```bash
kubectl apply -f k8s/external-secrets/sa.yaml
kubectl apply -f k8s/external-secrets/secretstore.yaml
kubectl apply -f k8s/external-secrets/externalsecrets.yaml
```

Verify secrets are synced:
```bash
kubectl get externalsecret -n retail-app
# STATUS should be SecretSynced for catalog-db and orders-db
```

### 5. App Deployment

```bash
helm upgrade --install retail-store ./helm \
  --namespace retail-app --create-namespace \
  --wait
```

Apply ingress and RBAC:
```bash
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/rbac/dev-view-binding.yaml
```

Get the app URL:
```bash
kubectl get ingress retail-ui -n retail-app
```

The ADDRESS column is the ALB DNS name.

### 6. GitHub Actions CI/CD

Set the AWS role ARN as a repository secret:
```bash
gh secret set AWS_ROLE_ARN \
  --body "$(cd terraform && terraform output -raw github_actions_role_arn)" \
  --repo alexindevs/project-bedrock
```

- PRs targeting `main` that touch `terraform/**` will receive a plan comment.
- Merges to `main` that touch `terraform/**` will auto-apply.

---

## Tear Down

```bash
cd terraform
terraform destroy
```

RDS and EKS both take ~10-15 minutes to provision and delete. Everything else is fast, save for NAT Gateways, which take about 5 minutes.

---

## Dev Access

A read-only IAM user `bedrock-dev-view` exists with:
- AWS `ReadOnlyAccess` + `s3:PutObject` on the assets bucket
- EKS `view` ClusterRole via the `bedrock-viewers` group

Access key creation (run once, store securely):
```bash
aws iam create-access-key --user-name bedrock-dev-view
```
