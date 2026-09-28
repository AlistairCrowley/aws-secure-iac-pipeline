output "bucket_name" {
  description = "Name of the data bucket"
  value       = aws_s3_bucket.data.bucket
}

output "bucket_arn" {
  description = "ARN of the data bucket"
  value       = aws_s3_bucket.data.arn
}

output "reader_role_arn" {
  description = "ARN of the read-only IAM role"
  value       = aws_iam_role.reader.arn
}