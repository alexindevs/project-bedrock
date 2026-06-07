output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}
 
output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}
 
output "region" {
  description = "AWS region."
  value       = var.region
}
 
output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}
 
output "assets_bucket_name" {
  description = "Name of the S3 assets bucket."
  value       = aws_s3_bucket.assets.id
}
