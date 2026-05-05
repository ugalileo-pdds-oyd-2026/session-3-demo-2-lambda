# infra/backend.tf
terraform {
  backend "s3" {
    bucket         = "tito-terraform-demo-state"
    key            = "session3/demo-b-lambda/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-demo-locks"
    encrypt        = true
  }
}
