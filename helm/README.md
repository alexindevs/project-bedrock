# Retail Store - Helm Chart

Custom Helm chart deploying the AWS Retail Store Sample App (v0.8.5) on EKS,
with the data layer pointed at managed AWS services.

| Service   | Backend                          |
|-----------|----------------------------------|
| catalog   | RDS MySQL 8.0 (`project-bedrock-catalog`) |
| orders    | RDS PostgreSQL 16 (`project-bedrock-orders`) |
| carts     | DynamoDB (`project-bedrock-carts`) via IRSA |
| checkout  | Redis (in-cluster)               |
| orders broker | RabbitMQ (in-cluster)        |

Database credentials are injected at runtime via External Secrets Operator,
which syncs passwords from AWS Secrets Manager into Kubernetes Secrets.

## Prerequisites

- Terraform applied (EKS, RDS, DynamoDB, IRSA roles, S3, Lambda, GitHub OIDC).
- kubeconfig pointed at `project-bedrock-cluster` (us-east-1):
  ```bash
  aws eks update-kubeconfig --name project-bedrock-cluster --region us-east-1
  ```
- External Secrets Operator installed and secrets synced in `retail-app`:
  ```bash
  kubectl get externalsecret -n retail-app
  ```

## Deploy

```bash
helm upgrade --install retail-store ./helm \
  --namespace retail-app --create-namespace \
  --wait
```

## Verify

```bash
kubectl get pods -n retail-app
kubectl get ingress retail-ui -n retail-app
```

The ALB DNS name from `kubectl get ingress` is the app entry point.

## Uninstall

```bash
helm uninstall retail-store -n retail-app
```
