output "namespace_name" {
  description = "The name of the Redshift Serverless namespace."
  value       = aws_redshiftserverless_namespace.this.namespace_name
}

output "namespace_arn" {
  description = "The ARN of the Redshift Serverless namespace."
  value       = aws_redshiftserverless_namespace.this.arn
}

output "workgroup_name" {
  description = "The name of the Redshift Serverless workgroup."
  value       = aws_redshiftserverless_workgroup.this.workgroup_name
}

output "workgroup_id" {
  description = "The unique identifier of the workgroup."
  value       = aws_redshiftserverless_workgroup.this.id
}

output "workgroup_endpoint" {
  description = "Endpoint information for connecting via JDBC/ODBC."
  value = {
    address = aws_redshiftserverless_workgroup.this.endpoint[0].address
    port    = aws_redshiftserverless_workgroup.this.endpoint[0].port
  }
}
