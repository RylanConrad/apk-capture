variable "aws-region" {
    description = "aws-region used for instance"
    type = string 
    default = "us-east-1"
}

variable "transfer_public_key" {
    description = "transferuser password"
    type = string 
    default = "<PASTE_VENDORS_KEY_HERE>"
}
