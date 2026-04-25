# 🎬 Netflix Clone on AWS (Terraform)

A production-grade, cloud-native video streaming platform built using Terraform and AWS.

This project demonstrates real-world cloud architecture patterns including:
- Infrastructure as Code (Terraform)
- Serverless backend (Lambda + API Gateway)
- Global CDN delivery (CloudFront)
- Secure video streaming (Signed URLs)
- Authentication (Cognito)
- CI/CD (GitHub Actions)
- Network isolation (VPC + private subnets)
- Edge security (WAF)

---

## 🧱 Architecture
Here's a summary of the data flows:

User traffic hits WAF first, then CloudFront serves static content from the output S3 bucket

API calls go through API Gateway → Lambda → DynamoDB for video metadata

Video uploads land in the input S3 bucket → MediaConvert processes them → output goes to the output S3 bucket

Cognito handles user authentication separately

The VPC provides network isolation with public/private subnets, though Lambda and API Gateway are currently not placed inside it

Global S3 + DynamoDB handle Terraform remote state and locking
#####

1. Connect the pieces (nothing is wired together yet)
API Gateway has no Lambda integration — requests hit the API but never reach Lambda
Lambda has no DynamoDB permissions — it can't read/write the videos-dev table
MediaConvert has no S3 trigger — uploads to the input bucket don't start a job
CloudFront has no OAC/OAI — the S3 output bucket is likely blocking public access

2. Fix IAM permissions
Lambda needs policies for DynamoDB, S3, and CloudWatch Logs
MediaConvert role needs S3 read/write permissions
Right now both are roles with no attached policies — they can't do anything

3. Build out the backend
backend/index.js exists but Lambda isn't deploying it — the CI/CD pipeline needs to zip and upload it
Add routes to API Gateway (GET /videos, POST /videos, etc.)

4. Frontend
No frontend exists yet — you'd need a React/Next.js app hosted on the S3 output bucket served via CloudFront
Integrate Cognito for auth (Amplify makes this straightforward)

5. CI/CD pipeline