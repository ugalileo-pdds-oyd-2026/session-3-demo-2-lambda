module "compute_lambda" {
  source = "./modules/compute_lambda"

  environment = var.environment
  name        = var.name
  memory_size = var.memory_size
}
