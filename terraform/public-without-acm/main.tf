# 1. Provider
provider "aws" {
  region = "us-east-1"
}

# 2. S3 Bucket (public)
resource "aws_s3_bucket" "static_site_bucket" {
  bucket = var.bucket_name  # Make sure this is unique, this variable is set in varibles.tf

  tags = {
    Name        = "StaticSiteBucket"
    Environment = "Dev"
  }
}

# 2.1 Disable public access block for public bucket
resource "aws_s3_bucket_public_access_block" "static_site_bucket_block" {
  bucket = aws_s3_bucket.static_site_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 2.2 Make bucket public via bucket policy (replaces deprecated ACL)
resource "aws_s3_bucket_policy" "public" {
  bucket = aws_s3_bucket.static_site_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = "${aws_s3_bucket.static_site_bucket.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.static_site_bucket_block]
}

# 3. CloudFront Origin Access Control (optional for public bucket)
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.bucket_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 4. WAF Web ACL (optional)
resource "aws_wafv2_web_acl" "web_acl" {
  name  = "${var.bucket_name}-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "webACL"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }
}

# 5. CloudFront Distribution (no custom domain)
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  comment             = "CDN for static site"
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.static_site_bucket.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.static_site_bucket.bucket}"

    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.static_site_bucket.bucket}"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  price_class = "PriceClass_100"

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  web_acl_id = aws_wafv2_web_acl.web_acl.arn
}

# 6. ACM / Route53 (commented out for public S3 bucket)
# resource "aws_acm_certificate" "cert" { ... }
# resource "aws_route53_record" "cert_validation" { ... }
# resource "aws_acm_certificate_validation" "cert_validation" { ... }
# resource "aws_route53_record" "alias" { ... }

#7. Upload index.html to S3
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.static_site_bucket.id
  key          = "index.html"
  source       = "${path.module}/index.html"   # Make sure index.html exists in same folder
  content_type = "text/html"

  # No ACL needed if using BucketOwnerEnforced
  #acl    = "public-read"

  depends_on = [
    aws_s3_bucket_policy.public          # Ensure bucket policy exists
  ]
}

