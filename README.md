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

For a full breakdown of how the system is designed, see [ARCHITECTURE.md](ARCHITECTURE.md).

To deploy or tear down the stack, see [RUNBOOK.md](RUNBOOK.md).

If something is broken, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
