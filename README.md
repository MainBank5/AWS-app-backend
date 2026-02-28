# AWS Backend Infrastructure — Terraform Deployment

A mock deployment of a production-style AWS architecture built entirely with Terraform. The goal of this project was to demonstrate core cloud networking concepts including VPC design, load balancing, auto scaling, and managed database provisioning.

---

## Architecture Overview

Think of the VPC as a city inside the vast country of AWS. Inside that city, subnets are the neighborhoods — logical network divisions that help organise resources and make access control easier to manage.

The architecture follows a classic 3-tier pattern:

- **VPC** — isolated network environment hosting all resources
- **Public Subnets (x2)** — spread across two Availability Zones for high availability, hosting the EC2 instances and load balancer
- **Internet Gateway** — the front door connecting the VPC to the public internet
- **Route Table** — directs internet-bound traffic (`0.0.0.0/0`) through the IGW to the public subnets
- **Application Load Balancer (ALB)** — distributes incoming HTTP traffic across EC2 instances to improve performance and resilience
- **Auto Scaling Group (ASG)** — automatically manages EC2 instance count based on demand, using an Ubuntu 22.04 Launch Template
- **Aurora PostgreSQL Cluster** — managed relational database, hidden from public access and only reachable from EC2 instances
- **Security Groups** — act as traffic cops, enforcing rules on what traffic can reach each resource

---

## Technologies Used

- Terraform
- AWS VPC, Subnets, Internet Gateway, Route Tables
- AWS EC2, Launch Templates, Auto Scaling Groups
- AWS Application Load Balancer, Target Groups
- AWS Aurora PostgreSQL
- AWS IAM
- AWS Key Pairs (generated via Terraform `tls_private_key`)

---

## Security Decisions

**Separate security group for Aurora** — the RDS cluster has its own dedicated security group that only accepts traffic on port 5432 from the EC2 security group. This means the database is completely hidden from the public internet and can only be reached by the application instances. This pattern is called security group chaining and is a real-world best practice.

**SSH restricted to a dynamic IP** — rather than opening port 22 to the world (`0.0.0.0/0`), the SSH ingress rule is locked to the deployer's current public IP, fetched automatically at apply time using the `http` data source.

**Secrets kept out of source control** — database credentials are stored in `secrets.auto.tfvars` which is listed in `.gitignore` along with the private key file and Terraform state files.

---

## Prerequisites

- Terraform installed locally
- AWS CLI installed and configured (`aws configure`)
- An IAM user with sufficient permissions and active access keys
- Basic Terraform knowledge

---

## Deployment

```bash
# Initialise Terraform and download providers
terraform init

# Preview the planned infrastructure changes
terraform plan -out=tfplan

# Apply the plan
terraform apply tfplan
```

---

## Teardown

Before destroying, disable deletion protection on the load balancer by setting `enable_deletion_protection = false` in `main.tf`, then apply that change first:

```bash
terraform apply
terraform destroy
```

> **Note:** Skipping the deletion protection step will cause `terraform destroy` to fail on the ALB resource.

---

## Challenges Faced

**ALB requires two subnets in different Availability Zones** — Terraform itself does not enforce this, but AWS rejects the load balancer at apply time if both subnets are in the same AZ. This was a good lesson that `terraform plan` validates syntax and logic but cannot catch all AWS-side constraints.

**Aurora PostgreSQL engine version** — specifying an invalid version like `15.4` passes `terraform plan` cleanly but fails at apply time when AWS actually tries to provision the cluster. Always verify supported engine versions in the AWS console before applying.

**Deletion protection blocking destroy** — the ALB was configured with deletion protection enabled, which prevented `terraform destroy` from completing. The fix was to disable the protection via `terraform apply` before running destroy.

**AWS CLI credentials** — misconfigured or invalidated access keys produce a confusing STS error. The fix is to rotate keys in IAM and reconfigure the AWS CLI.

---

## Future Improvements

- Move the Aurora cluster into **private subnets** so it has no route to the internet at all — currently it sits in public subnets which is not ideal for production
- Configure **Route 53** with a custom domain so users can access the app via a proper URL rather than the ALB DNS name
- Add **HTTPS** via AWS Certificate Manager and update the ALB listener to port 443
- Add **CloudFront** as a CDN layer in front of the ALB for improved global performance
- Set up **CloudWatch** monitoring and billing alerts to track traffic and infrastructure costs
- Refactor into **Terraform modules** for reusability and cleaner code structure


<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/d508eca0-9e9a-44a1-a1f6-abf790fa25fe" />

