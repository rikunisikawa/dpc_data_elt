-- Bootstrap script for initializing Redshift Serverless schemas
-- Execute via Redshift Data API or any SQL client after the namespace is provisioned.

create schema if not exists raw;
create schema if not exists stage;
create schema if not exists mart;
create schema if not exists ref;
create schema if not exists dq;
