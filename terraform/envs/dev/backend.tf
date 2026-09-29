# State remoto por ambiente: bucket cifrado con KMS, versionado y con lock
# nativo de S3 (use_lockfile). El rol de deploy de dev solo puede escribir
# bajo envs/dev/.
terraform {
  backend "s3" {
    bucket       = "prueba-devops-tfstate-766531847729"
    key          = "envs/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
