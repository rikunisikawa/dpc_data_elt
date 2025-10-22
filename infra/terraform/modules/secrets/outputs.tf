output "secret_arns" {
  description = "ARNs of the Secrets Manager secrets."
  value = {
    for key, secret in aws_secretsmanager_secret.this : key => secret.arn
  }
}
