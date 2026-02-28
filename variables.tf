variable "region_1" {
  default = "us-east-1a"
}

variable "region_2" {
  default = "us-east-1b"
}

variable "db_username" {
  type      = string
  sensitive = true
  default   = "mydbuser"
}

variable "db_password" {
  type      = string
  sensitive = true
}
