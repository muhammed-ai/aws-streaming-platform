terraform {
  backend "s3" {
    bucket         = "netflix-tf-state-12345-unique"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
  }
}

