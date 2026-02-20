This is a guide on how to setup a secure cloud-based SFTP transfer server.
It uses EC2 attached to an elastic Public IP, then stores the files in a standard S3 bucket.

### Setup - Install Terraform, Connect to AWS
- [Terraform install guide](https://github.com/PureLogicIT/103-terraform/tree/main/00-install-terraform)
- ``` bash
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  ```
#### - Setup access key
	- Login to AWS console.
	- Click username in top right corner
	- Click "Security credentials"
	- Scroll down to "Access Keys"
	- Create access key - CLI - Next
	- Copy - **AWS Access Key ID:** `AKIA...` & **AWS Secret Access Key:** `wJalr...`
#### - Connect to AWS
``` bash
# paste in Access Key and Secret Access Key when prompted
aws configure
```
#### - Test connection
- ``` bash
  aws sts get-caller-identity
  ```

## Paste in public key
- Navigate to apk-capture/terraform/variables.tf
- Paste in the vendors public key
``` HCL
variable "transfer_public_key" {
    description = "transferuser password"
    type = string 
    default = "<PASTE_VENDORS_KEY_HERE>"
}
```

## Start Resources
``` bash
cd apk-capture/terraform
# See the infrastructure plan
terraform plan
# Build for real
terraform apply
```

## Vendor guide
To securely send us your APK:

``` bash
# From the workstation you gave us the public key from.
sftp transferuser@44.205.201.65
```
##### sftp> put app.apk s3-uploads/