resource "aws_dynamodb_table" "carts" {
  name         = "project-bedrock-carts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "customerId"
    type = "S"
  }

  global_secondary_index {
    name            = "idx_global_customerId"
    hash_key        = "customerId"
    projection_type = "ALL"
  }
}

data "aws_iam_policy_document" "carts_dynamo" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      aws_dynamodb_table.carts.arn,
      "${aws_dynamodb_table.carts.arn}/index/*",
    ]
  }
}

resource "aws_iam_policy" "carts_dynamo" {
  name   = "project-bedrock-carts-dynamodb"
  policy = data.aws_iam_policy_document.carts_dynamo.json
}

data "aws_iam_policy_document" "carts_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:retail-app:carts"]
    }
  }
}

resource "aws_iam_role" "carts" {
  name               = "project-bedrock-carts-role"
  assume_role_policy = data.aws_iam_policy_document.carts_assume.json
}

resource "aws_iam_role_policy_attachment" "carts_dynamo" {
  role       = aws_iam_role.carts.name
  policy_arn = aws_iam_policy.carts_dynamo.arn
}

output "carts_role_arn" {
  description = "Annotate the carts service account with this ARN."
  value       = aws_iam_role.carts.arn
}
