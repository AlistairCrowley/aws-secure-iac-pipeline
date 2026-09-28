variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name used to label and prefix every resource"
  type        = string
  default     = "secure-iac-pipeline"
}