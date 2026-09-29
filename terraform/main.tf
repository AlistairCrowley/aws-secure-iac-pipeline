resource "aws_s3_bucket" "data" {
  bucket_prefix = "${var.project_name}-data-"
}


resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "data_key" {
  #checkov:skip=CKV_AWS_109:Key policy - kms:* is scoped to this key only and delegated to IAM (AWS default key policy)
  #checkov:skip=CKV_AWS_111:Key policy - write actions apply only to the key this policy is attached to
  #checkov:skip=CKV_AWS_356:Key policy - resource * refers to this key itself, not all resources

  statement {
    sid       = "EnableIAMPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]


    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}


resource "aws_kms_key" "data" {
  description             = "Encrypts objects in the project data bucket"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.data_key.json

}

resource "aws_kms_alias" "data" {
  name          = "alias/${var.project_name}-data"
  target_key_id = aws_kms_key.data.key_id
}


resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true
  }
}


resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  depends_on = [aws_s3_bucket_versioning.data]

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}



data "aws_iam_policy_document" "reader_trust" {
  statement {
    sid     = "AllowEC2ToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}


resource "aws_iam_role" "reader" {
  name_prefix        = "${var.project_name}-reader-"
  description        = "Read-only access to the project data bucket"
  assume_role_policy = data.aws_iam_policy_document.reader_trust.json
}


data "aws_iam_policy_document" "reader_permissions" {
  statement {
    sid       = "ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data.arn]
  }

  statement {
    sid       = "ReadObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data.arn}/*"]
  }

  statement {
    sid       = "DecryptWithDataKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.data.arn]
  }

}


resource "aws_iam_role_policy" "reader" {
  name   = "read-data-bucket"
  role   = aws_iam_role.reader.id
  policy = data.aws_iam_policy_document.reader_permissions.json
}



resource "aws_s3_bucket" "logs" {
 #checkov:skip=CKV_AWS_145:Log destination bucket - S3 server access logging does not support customer-managed KMS keys so SSE-S3 (AES256) is used   
  bucket_prefix = "${var.project_name}-logs-"
}


resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

  }
}


resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}



resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  depends_on = [aws_s3_bucket_versioning.logs]

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = 365
    }
  }
}


data "aws_iam_policy_document" "logs_bucket" {
  statement {
    sid       = "AllowS3ServerAcessLogs"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/access-logs/*"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.data.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket.json
}


resource "aws_s3_bucket_logging" "data" {
  bucket        = aws_s3_bucket.data.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "access-logs/"
}