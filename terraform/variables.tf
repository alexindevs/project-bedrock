variable "region" {
  description = "AWS region (mandated)."
  type        = string
  default     = "us-east-1"
}
 
variable "cluster_name" {
  description = "EKS cluster name (mandated)."
  type        = string
  default     = "project-bedrock-cluster"
}
 
variable "cluster_version" {
  description = "Kubernetes version (must be >= 1.34)."
  type        = string
  default     = "1.34"
}
 
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "student_id" {
  description = "Lowercased, hyphenated student id used in bucket names."
  type        = string
  default     = "alt-soe-025-5437"
}
