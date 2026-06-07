# Runbook - Project Bedrock

This walks through deploying the full stack from scratch. The steps need to be done in order because each one depends on the previous. Roughly: provision infrastructure with Terraform, install the cluster add-ons, then deploy the app.

---

## Prerequisites

You need the AWS CLI configured with credentials that have broad permissions (AdministratorAccess works), plus Terraform >= 1.9, `kubectl`, `helm`, and the `gh` CLI.

---

## Step 1 - Bootstrap Terraform Remote State

The S3 bucket for Terraform state has to exist before you can run `terraform init`, so it can't be managed by Terraform itself. Run these commands once:

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

---

## Step 2 - Terraform

This step provisions everything: VPC, EKS cluster and node group, RDS instances, DynamoDB table, S3 bucket, Lambda, all IAM roles, Secrets Manager secrets, and the OIDC provider.

```bash
cd terraform
terraform init
terraform apply
```

EKS and RDS each take around 10-15 minutes. NAT Gateways are about 5 minutes. Once it finishes, pull down the kubeconfig:

```bash
aws eks update-kubeconfig \
  --name project-bedrock-cluster \
  --region us-east-1
```

Run `kubectl get nodes` to confirm the two nodes are Ready before moving on.

---

## Step 3 - AWS Load Balancer Controller

Terraform already created the IRSA role. Apply the service account (it has the role ARN annotation baked in) and then install the controller with Helm:

```bash
kubectl apply -f k8s/lb-controller/sa.yaml
```

```bash
VPC_ID=$(terraform output -raw vpc_id)

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

Check it came up cleanly:

```bash
kubectl rollout status deployment aws-load-balancer-controller -n kube-system
```

---

## Step 4 - External Secrets Operator

Install ESO into its own namespace first, then apply the service account, SecretStore, and ExternalSecrets for the app:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --set installCRDs=true \
  --wait
```

```bash
kubectl apply -f k8s/external-secrets/sa.yaml
kubectl apply -f k8s/external-secrets/secretstore.yaml
kubectl apply -f k8s/external-secrets/externalsecrets.yaml
```

Wait for both ExternalSecrets to sync before moving on, otherwise the catalog and orders pods will fail to start:

```bash
kubectl get externalsecret -n retail-app
```

Both `catalog-db` and `orders-db` should show `SecretSynced` in the STATUS column.

---

## Step 5 - App Deployment

Deploy everything via Helm, then apply the ingress and RBAC separately (they're not part of the Helm chart):

```bash
helm upgrade --install retail-store ./helm \
  --namespace retail-app --create-namespace \
  --wait
```

```bash
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/rbac/dev-view-binding.yaml
```

The ALB takes 2-3 minutes to provision after the ingress is applied. Get the URL with:

```bash
kubectl get ingress retail-ui -n retail-app
```

The ADDRESS column is the ALB DNS name. The app is also reachable at `https://44-197-2-76.nip.io`.

---

## Step 6 - GitHub Actions CI/CD

Set the AWS role ARN as a repository secret so the Actions workflow can authenticate via OIDC:

```bash
gh secret set AWS_ROLE_ARN \
  --body "$(cd terraform && terraform output -raw github_actions_role_arn)" \
  --repo alexindevs/project-bedrock
```

After this, PRs that touch `terraform/**` will get a plan comment, and merges to `main` will auto-apply.

---

## Making Changes After Deployment

To update a service or change config values, edit [helm/values.yaml](helm/values.yaml) or the relevant template in [helm/templates/](helm/templates/) and run:

```bash
helm upgrade retail-store ./helm --namespace retail-app --wait
```

The ingress isn't part of the Helm release, so changes to [k8s/ingress.yaml](k8s/ingress.yaml) need to be applied directly:

```bash
kubectl apply -f k8s/ingress.yaml
```

For infrastructure changes, open a PR against `terraform/**`. The workflow will post the plan. Merging applies it. For one-off manual changes, just `terraform plan` and `terraform apply` from the terraform directory.

---

## Tear Down

Not everything was created by Terraform, so `terraform destroy` alone will leave orphaned AWS resources. The order matters here - the Load Balancer Controller needs to be running when you delete the ingress so it can clean up the ALB and its associated target groups and security groups. If the ALB is still around when Terraform tries to delete the VPC, it will fail.

**Step 1 - Delete the ingress.** This tells the LBC to deprovision the ALB.

```bash
kubectl delete -f k8s/ingress.yaml
```

Wait until the ALB is gone before continuing. You can check in the AWS Console under EC2 > Load Balancers, or watch the ingress until the ADDRESS clears:

```bash
kubectl get ingress retail-ui -n retail-app -w
```

**Step 2 - Uninstall the Helm releases.**

```bash
helm uninstall retail-store -n retail-app
helm uninstall external-secrets -n external-secrets
helm uninstall aws-load-balancer-controller -n kube-system
```

**Step 3 - Delete the remaining kubectl-applied resources.**

```bash
kubectl delete -f k8s/external-secrets/externalsecrets.yaml
kubectl delete -f k8s/external-secrets/secretstore.yaml
kubectl delete -f k8s/external-secrets/sa.yaml
kubectl delete -f k8s/lb-controller/sa.yaml
kubectl delete -f k8s/rbac/dev-view-binding.yaml
```

**Step 4 - Terraform destroy.** This removes everything Terraform provisioned: EKS, RDS, DynamoDB, VPC, IAM roles, Secrets Manager secrets, S3 assets bucket, Lambda, and the OIDC provider.

```bash
cd terraform
terraform destroy
```

RDS and EKS each take around 10-15 minutes. NAT Gateways take about 5 minutes.

**Step 5 - Manual cleanup.** Two things exist outside Terraform state:

The tfstate bucket was created manually before Terraform was initialized. Delete it once you no longer need the state:

```bash
aws s3 rm s3://bedrock-tfstate-alt-soe-025-5437 --recursive
aws s3api delete-bucket --bucket bedrock-tfstate-alt-soe-025-5437 --region us-east-1
```

If an access key was created for `bedrock-dev-view`, deactivate and delete it:

```bash
# list keys to get the key id
aws iam list-access-keys --user-name bedrock-dev-view

aws iam delete-access-key \
  --user-name bedrock-dev-view \
  --access-key-id <key-id>
```
