# Terraform setup

Infrastructure-as-Code deployment via [`terraform-example/`](../terraform-example/). For step-by-step `gcloud` commands, see [Manual setup](manual-setup.md).

The Terraform module packages and deploys the function from [`secret-rotator/`](../secret-rotator/) and provisions:

- Required GCP APIs (Secret Manager, Pub/Sub, Cloud Functions, Cloud Run, Eventarc, Artifact Registry, etc.)
- Secret Manager service identity and Pub/Sub topic with publisher IAM
- A Secret Manager secret with rotation schedule and event notifications
- Artifact Registry service agent `secretAccessor` on the rotated secret (for GAR Connector mode repositories)
- A Cloud Function (Gen2) triggered by rotation events
- Service accounts and IAM bindings

JFrog OIDC provider and identity mapping are **not** managed by Terraform — configure those manually using [JFrog OIDC integration](manual-setup.md#jfrog-oidc-integration) and the Terraform outputs below.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- `gcloud` authenticated with permissions to create the resources above
- JFrog OIDC integration planned (provider name and target user)

## Quick start

```bash
cd terraform-example
cp terraform.tfvars.example terraform.tfvars   # edit with your values
terraform init
terraform plan
terraform apply
```

After apply, configure JFrog OIDC using the output values (see below), then wait for the first rotation (default: ~5 minutes after apply) or trigger one manually.

## Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `project_id` | yes | — | GCP project ID |
| `region` | yes | — | Region for the Cloud Function (e.g. `us-central1`) |
| `secret_name` | yes | — | Secret Manager secret ID |
| `rotation_period` | yes | — | Interval between rotations (e.g. `"36000s"`). Minimum `3600s` (1 hour) |
| `jfrog_host` | yes | — | JFrog hostname (e.g. `myregistry.jfrog.io`) |
| `provider_name` | yes | — | JFrog OIDC provider name |
| `pubsub_topic_name` | no | `jfrog-secret-rotation` | Pub/Sub topic for rotation events |
| `function_name` | no | `secret-rotation-function` | Cloud Function name |
| `function_service_account_id` | no | `secret-rotator-sa` | Function service account short name |
| `next_rotation_time` | no | ~5 min after apply | RFC3339 timestamp for first rotation |
| `audience` | no | `""` | OIDC audience; empty uses secret resource name |
| `prev_secret_action` | no | `KEEP` | Previous version handling: `KEEP`, `DESTROY`, or `DISABLE` |
| `jfrog_debug` | no | `false` | Enable debug logging |

See [`terraform.tfvars.example`](../terraform-example/terraform.tfvars.example) for a starter configuration.

## Outputs

After `terraform apply`, retrieve values for JFrog identity mapping:

```bash
terraform output function_service_account_email
terraform output default_audience
terraform output secret_resource_name
```

| Output | Use |
|--------|-----|
| `function_service_account_email` | JFrog identity mapping `email` claim |
| `default_audience` | JFrog identity mapping `aud` claim (when `audience` is unset) |
| `configured_audience` | Custom `aud` claim if `audience` variable was set |
| `secret_resource_name` | Full secret resource path |
| `project_number` | Project number for identity mapping |
| `cloud_function_name` | Deployed function name |

## JFrog identity mapping

Use Terraform outputs in the identity mapping from [JFrog OIDC integration](manual-setup.md#jfrog-oidc-integration):

```bash
PROJECT_NUMBER=$(terraform output -raw project_number)
SECRET_NAME=$(terraform output -raw secret_id)
FUNCTION_SA=$(terraform output -raw function_service_account_email)
AUDIENCE=$(terraform output -raw default_audience)
```

Set the `claims` in the identity mapping curl to:

```json
"claims": {
  "iss": "https://accounts.google.com",
  "aud": "<AUDIENCE or configured_audience>",
  "email": "<FUNCTION_SA>"
}
```

If you set the `audience` Terraform variable, use `terraform output -raw configured_audience` instead of `default_audience`.

Ensure JFrog `token_spec.expires_in` exceeds `rotation_period` by at least 30% (see [Token expiry vs rotation period](manual-setup.md#token-expiry-vs-rotation-period)). For the default example (`rotation_period = "36000s"`), use `expires_in: 46800`.

## Verify

After JFrog OIDC is configured, schedule the first rotation (or wait for `next_rotation_time`, default ~5 minutes after apply). See [Setting `NEXT_ROTATION_TIME`](manual-setup.md#setting-next_rotation_time):

```bash
NEXT_ROTATION_TIME=$(date -u -v+6M +"%Y-%m-%dT%H:%M:%SZ")   # macOS
# NEXT_ROTATION_TIME=$(date -u -d "+6 minutes" +"%Y-%m-%dT%H:%M:%SZ")   # GNU/Linux

gcloud secrets update "$(terraform output -raw secret_id)" \
  --next-rotation-time="$NEXT_ROTATION_TIME"
```

List versions and read the latest value:

```bash
gcloud secrets versions list "$(terraform output -raw secret_id)"
gcloud secrets versions access latest --secret="$(terraform output -raw secret_id)"
```

Check Cloud Function logs if rotation fails:

```bash
gcloud functions logs read "$(terraform output -raw cloud_function_name)" --gen2 --region=<your-region> --limit=50
```

See [First secret version](manual-setup.md#first-secret-version) for troubleshooting tips.

## Cleanup

```bash
cd terraform-example
terraform destroy
```
