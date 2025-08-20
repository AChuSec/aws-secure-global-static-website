# 1. Provider
provider "aws" {
  region = "us-east-1"
}

#1.1 Generate a short random suffix for unique names
resource "random_id" "suffix" {
  byte_length = 4  
}


# 2. S3 Bucket (private)
resource "aws_s3_bucket" "static_site_bucket" {
  bucket = var.bucket_name
  
  tags = {
    Name        = "StaticSiteBucket"
    Environment = "Dev"
  }

}

# 2.1 Block Public Access (separate resource), acl private is deprecated
resource "aws_s3_bucket_public_access_block" "static_site_bucket_block" {
  bucket = aws_s3_bucket.static_site_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. S3 Bucket Policy to allow CloudFront OAC access
data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    effect    = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.static_site_bucket.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.static_site_bucket.id
  policy = data.aws_iam_policy_document.s3_policy.json
}


# 4. CloudFront Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "oac" {
  name                      = "${var.bucket_name}-oac-${random_id.suffix.hex}"
  origin_access_control_origin_type = "s3"
  signing_behavior          = "always"
  signing_protocol          = "sigv4"
}

# 5. ACM Certificate (must be in us-east-1 for CloudFront)
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}


# 6. Route 53 DNS validation record for ACM cert
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

# 7. ACM Certificate validation
resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# 8. WAF Web ACL
resource "aws_wafv2_web_acl" "web_acl" {
  name        = "${var.bucket_name}-waf-${random_id.suffix.hex}"
  scope       = "CLOUDFRONT"
  description = "WAF ACL for static website"
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

# 9. CloudFront Distribution
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

  price_class = "PriceClass_100" # Use cheapest edges (US, Canada, Europe)

  viewer_certificate {
    acm_certificate_arn            = aws_acm_certificate.cert.arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  web_acl_id = aws_wafv2_web_acl.web_acl.arn

  aliases = [var.domain_name]
}

# 10. Route 53 Alias Record to CloudFront
resource "aws_route53_record" "alias" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

# 11. Upload index.html to private S3 bucket
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.static_site_bucket.id
  key          = "index.html"
  source       = "${path.module}/index.html"   # Make sure index.html exists in same folder
  content_type = "text/html"

  # No ACL needed since bucket is private and accessed via CloudFront OAC
  #acl        = "private"

  depends_on = [
    aws_s3_bucket_policy.bucket_policy,          # Ensure bucket policy exists
    aws_cloudfront_origin_access_control.oac     # Ensure OAC exists before upload
  ]
}

