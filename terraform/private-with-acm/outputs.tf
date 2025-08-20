# S3 Bucket
output "bucket_name" {
  description = "Name of the S3 bucket for the AWS Static Website"
  value       = aws_s3_bucket.static_site_bucket.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.static_site_bucket.arn
}

# CloudFront
output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn.id
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn.domain_name
}

# ACM Certificate
output "acm_certificate_arn" {
  description = "ARN of the ACM certificate used for HTTPS"
  value       = aws_acm_certificate.cert.arn
}


# WAF Web ACL
output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL associated with CloudFront"
  value       = aws_wafv2_web_acl.web_acl.arn
}