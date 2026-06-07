resource "aws_db_subnet_group" "this" {
  name       = "project-bedrock-db-subnets"
  subnet_ids = local.private_subnet_ids
}

locals {
  node_sg_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

resource "aws_security_group" "mysql" {
  name        = "project-bedrock-mysql-sg"
  description = "MySQL from EKS nodes only"
  vpc_id      = aws_vpc.this.id
}

resource "aws_security_group_rule" "mysql_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.mysql.id
  protocol                 = "tcp"
  from_port                = 3306
  to_port                  = 3306
  source_security_group_id = local.node_sg_id
}

resource "aws_security_group" "postgres" {
  name        = "project-bedrock-postgres-sg"
  description = "PostgreSQL from EKS nodes only"
  vpc_id      = aws_vpc.this.id
}

resource "aws_security_group_rule" "postgres_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.postgres.id
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  source_security_group_id = local.node_sg_id
}

resource "random_password" "mysql" {
  length  = 24
  special = false
}

resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "mysql" {
  name = "project-bedrock/catalog-mysql"
}

resource "aws_secretsmanager_secret_version" "mysql" {
  secret_id = aws_secretsmanager_secret.mysql.id
  secret_string = jsonencode({
    username = "catalog_user"
    password = random_password.mysql.result
    dbname   = "catalog"
    port     = 3306
  })
}

resource "aws_secretsmanager_secret" "postgres" {
  name = "project-bedrock/orders-postgres"
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id = aws_secretsmanager_secret.postgres.id
  secret_string = jsonencode({
    username = "orders_user"
    password = random_password.postgres.result
    dbname   = "orders"
    port     = 5432
  })
}

resource "aws_db_instance" "mysql" {
  identifier     = "project-bedrock-catalog"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  db_name  = "catalog"
  username = "catalog_user"
  password = random_password.mysql.result

  allocated_storage      = 20
  storage_type           = "gp3"
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.mysql.id]

  multi_az            = false
  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false
}

resource "aws_db_instance" "postgres" {
  identifier     = "project-bedrock-orders"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  db_name  = "orders"
  username = "orders_user"
  password = random_password.postgres.result

  allocated_storage      = 20
  storage_type           = "gp3"
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  multi_az            = false
  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false
}

data "aws_iam_policy_document" "eso" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      aws_secretsmanager_secret.mysql.arn,
      aws_secretsmanager_secret.postgres.arn,
    ]
  }
}

resource "aws_iam_policy" "eso" {
  name   = "project-bedrock-eso-read"
  policy = data.aws_iam_policy_document.eso.json
}

data "aws_iam_policy_document" "eso_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:retail-app:external-secrets-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "project-bedrock-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso.arn
}

output "eso_role_arn" {
  description = "Annotate the external-secrets-sa service account with this ARN."
  value       = aws_iam_role.eso.arn
}

output "mysql_address" {
  description = "RDS MySQL hostname (use in catalog patch)."
  value       = aws_db_instance.mysql.address
}

output "postgres_address" {
  description = "RDS PostgreSQL hostname (use in orders patch)."
  value       = aws_db_instance.postgres.address
}
