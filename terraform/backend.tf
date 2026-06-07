terraform {
  backend "s3" {
    bucket       = "bedrock-tfstate-alt-soe-025-5437"
    key          = "project-bedrock/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
