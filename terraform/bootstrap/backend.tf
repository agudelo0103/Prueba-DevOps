# El bootstrap se aplica primero con state local (el bucket aún no existe) y
# luego se migra aquí con: terraform init -migrate-state
terraform {
  backend "s3" {
    bucket       = "prueba-devops-tfstate-766531847729"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
