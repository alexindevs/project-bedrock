resource "aws_iam_user" "dev" {
  name = "bedrock-dev-view"
}

resource "aws_iam_user_policy_attachment" "dev_readonly" {
  user       = aws_iam_user.dev.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "dev_s3_put" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.assets_bucket}/*"]
  }
}

resource "aws_iam_user_policy" "dev_s3_put" {
  name   = "bedrock-dev-view-s3-put"
  user   = aws_iam_user.dev.name
  policy = data.aws_iam_policy_document.dev_s3_put.json
}

resource "aws_eks_access_entry" "dev" {
  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = aws_iam_user.dev.arn
  type              = "STANDARD"
  kubernetes_groups = ["bedrock-viewers"]
}
