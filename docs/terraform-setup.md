# Terraform setup

Infrastructure-as-Code deployment via [`terraform-example/`](../terraform-example/). For step-by-step `gcloud` commands,
see [Manual setup](manual-setup.md).

The Terraform module packages and deploys the function from [`secret-rotator/`](../secret-rotator/) and provisions:

- Required GCP APIs (Secret Manager, Pub/Sub, Cloud Functions, Cloud Run, Eventarc, Artifact Registry, etc.)
- Secret Manager service identity and Pub/Sub topic with publisher IAM
- A Secret Manager secret with rotation schedule and event notifications
- Artifact Registry service agent `secretAccessor` on the rotated secret (for Artifact Registry Connector mode repositories)
- A Cloud Function (Gen2) triggered by rotation events
- Service accounts and IAM bindings
- **JFrog OIDC provider and identity mapping** (when `create_jfrog_oidc = true`, the default)
- **Optional connector + Cloud Run example** (when `create_cloud_run_example = true`): JFrog local + Docker Hub
  remote + virtual Docker repos, Artifact Registry connector (`no_cache`), and a public Nginx Cloud Run service
  that pulls `nginx:latest` through Artifactory

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- `gcloud` authenticated with permissions to create the resources above
- JFrog Platform (Enterprise and above) with REST API access for OIDC management
- When `create_jfrog_oidc = true` (default):
- A JFrog platform admin access token (`jfrog_access_token` terraform variable or a `JFROG_ACCESS_TOKEN` environment
variable)
  - An existing JFrog user (`jfrog_user`) to receive rotated access tokens
- When `create_jfrog_oidc = false`:
  - An existing JFrog OIDC provider and identity mapping - see [Using existing JFrog OIDC](#using-existing-jfrog-oidc)

## Quick start

```bash
cd terraform-example
cp terraform.tfvars.example terraform.tfvars   # edit with your values
export JFROG_ACCESS_TOKEN="your-admin-token"   # or set jfrog_access_token in tfvars
terraform init
terraform plan
terraform apply
```

After apply, wait for the first rotation (default: ~6 minutes after plan) or trigger one manually.

When `create_cloud_run_example = true`, Terraform itself waits for that first rotation (printing reason and time
left) before creating the Artifact Registry connector, so a single apply can cover rotator + connector + Cloud Run.
The wait exits immediately if `versions/latest` is already a real token.

Unless you pin `next_rotation_time`, every apply reschedules the first rotation to ~6 minutes after that plan, so
repeated applies keep deferring a *new* scheduled rotation (the connector wait resource does not re-sleep on later
applies). To rotate on demand instead of waiting on the schedule, publish a `SECRET_ROTATE` event:

```bash
gcloud pubsub topics publish "$(terraform output -raw pubsub_topic_id)" \
  --attribute=eventType=SECRET_ROTATE \
  --message="{\"name\":\"projects/$(terraform output -raw project_number)/secrets/$(terraform output -raw secret_id)\"}"
```

## Variables

| Variable | Required | Default | Description |
| ---------- | ---------- | --------- | ------------- |
| `project_id` | yes | - | GCP project ID |
| `region` | yes | - | Region for the Cloud Function (e.g. `us-central1`) |
| `secret_name` | yes | - | Secret Manager secret ID |
| `rotation_period` | yes | - | Interval between rotations (e.g. `"36000s"`). Minimum `3600s` (1 hour) |
| `jfrog_host` | yes | - | JFrog hostname (e.g. `myregistry.jfrog.io`) |
| `provider_name` | yes | - | JFrog OIDC provider name |
| `create_jfrog_oidc` | no | `true` | Create JFrog OIDC provider and identity mapping via Terraform |
| `jfrog_user` | when `create_jfrog_oidc` or `create_cloud_run_example` | - | JFrog username for OIDC mapping and connector upstream auth |
| `jfrog_access_token` | when OIDC or JFrog Docker repos are created | - | JFrog admin token; can use `JFROG_ACCESS_TOKEN` env var instead |
| `jfrog_token_expires_in` | no | `rotation_period × 1.3` | JFrog access token lifetime (seconds) in the identity mapping |
| `oidc_mapping_name` | no | `provider_name` | Name of the JFrog OIDC identity mapping |
| `oidc_mapping_priority` | no | `1` | Identity mapping priority (lower = higher priority) |
| `pubsub_topic_name` | no | `jfrog-secret-rotation` | Pub/Sub topic for rotation events |
| `function_name` | no | `secret-rotation-function` | Cloud Function name |
| `function_service_account_id` | no | `secret-rotator-sa` | Function service account short name |
| `next_rotation_time` | no | ~6 min after plan | RFC3339 timestamp for first rotation |
| `audience` | no | `""` | OIDC audience; empty uses secret resource name |
| `prev_secret_action` | no | `DESTROY` | Previous version handling: `KEEP`, `DESTROY`, or `DISABLE`. With `create_cloud_run_example`, `DESTROY` is coerced to `KEEP` |
| `jfrog_debug` | no | `false` | Enable debug logging |
| `bootstrap_jfrog_token` | no | `dummy-token` placeholder | Initial Secret Manager version for Google Artifact Registry/consumers before first rotation |
| `create_cloud_run_example` | no | `false` | Create Artifact Registry connector + Cloud Run Nginx example; apply waits for first rotation when needed |
| `create_jfrog_docker_repos` | no | `true` | When the Cloud Run example is enabled, create JFrog local+remote+virtual Docker repos (set `false` to reuse existing keys) |
| `jfrog_docker_local_key` | no | `connector-docker-local` | JFrog local Docker repository key |
| `jfrog_docker_remote_key` | no | `connector-docker-remote` | JFrog remote Docker Hub repository key |
| `jfrog_docker_virtual_key` | no | `connector-docker` | JFrog virtual Docker repository key (connector upstream) |
| `connector_repository_id` | no | `jfrog-docker-connector` | Artifact Registry connector repository ID |
| `cloud_run_service_name` | no | `nginx-via-jfrog-connector` | Cloud Run service name |
| `cloud_run_image_name` | no | `nginx` | Image name pulled via the connector |
| `cloud_run_image_tag` | no | `latest` | Image tag pulled via the connector (from Docker Hub through Artifactory) |

See [`terraform.tfvars.example`](../terraform-example/terraform.tfvars.example) for a starter configuration.

The first Secret Manager version is seeded with `bootstrap_jfrog_token`, or the placeholder value `dummy-token` when
that is unset. The rotation function replaces it on the first successful `SECRET_ROTATE` event.

> **Note:** If you leave `bootstrap_jfrog_token` unset, the initial secret version holds the placeholder `dummy-token`,
> which is **not** a valid JFrog access token. Consumers such as authenticated Google Artifact Registry remote
> repositories will fail until the first rotation completes. To have a working token immediately after apply, either
> wait for the first rotation to complete or pre-set `bootstrap_jfrog_token` with a valid initial JFrog access token.

## JFrog OIDC (managed by Terraform)

When `create_jfrog_oidc = true` (default), Terraform creates:

1. **`platform_oidc_configuration`** - generic Google OIDC provider (`issuer_url = https://accounts.google.com`)
2. **`platform_oidc_identity_mapping`** - maps the rotation function's Google ID token to `jfrog_user`

The identity mapping `claims` are derived from GCP resources at apply time:

| Claim | Source |
| --- | --- |
| `iss` | `https://accounts.google.com` |
| `aud` | `audience` variable, or `projects/<project_number>/secrets/<secret_name>` |
| `email` | Rotation function service account email |

`token_spec.expires_in` defaults to `rotation_period × 1.3` (e.g. `46800` for `rotation_period = "36000s"`). Override
with `jfrog_token_expires_in` if needed.

Provide JFrog credentials via `jfrog_access_token` in `terraform.tfvars` or the `JFROG_ACCESS_TOKEN` environment
variable.

## Using existing JFrog OIDC

Set `create_jfrog_oidc = false` when the JFrog OIDC provider and identity mapping already exist (for example, created
manually or by another Terraform stack).

```hcl
create_jfrog_oidc = false
provider_name     = "gcp-oidc"   # must match your existing OIDC provider name
# audience        = "..."        # only if your existing mapping uses a custom aud claim
```

### What Terraform still manages

GCP resources (secret, function, IAM, etc.) are always created. Only the JFrog `platform_oidc_configuration` and
`platform_oidc_identity_mapping` resources are skipped.

### What you must ensure manually

Your existing JFrog setup must match what the rotation function emits at runtime. After `terraform apply`, verify these
align:

| Setting | Must match |
| --------- | ------------ |
| `provider_name` variable | Existing OIDC provider name in JFrog |
| `aud` claim in identity mapping | `terraform output default_audience` (or `configured_audience` if `audience` is set) |
| `email` claim in identity mapping | `terraform output function_service_account_email` |
| `iss` claim | `https://accounts.google.com` |
| `token_spec.expires_in` | At least 30% longer than `rotation_period` - see `terraform output jfrog_token_expires_in` for the recommended value |
| `token_spec.username` | A valid JFrog user with required permissions |

Configure or update the mapping using [JFrog OIDC integration](manual-setup.md#jfrog-oidc-integration) and the Terraform
outputs below.

### Impact of using existing OIDC

- **No JFrog admin token required** - `jfrog_access_token` / `JFROG_ACCESS_TOKEN` are not needed for apply.
- **Claims must be updated after apply** - the function service account email is only known once GCP resources are
  created. If you pre-created a mapping with placeholder claims, update it after the first `terraform apply` using the
  outputs.
- **`provider_name` conflicts** - if an existing provider with the same name has different settings (issuer, type), the
  rotation function will still reference that name via `PROVIDER_NAME` but Terraform will not reconcile it. Ensure the
  existing provider is configured for Google OIDC (`issuer_url = https://accounts.google.com`, type generic).
- **Re-apply / SA changes** - if you change `function_service_account_id` and Terraform recreates the service account,
  you must update the `email` claim in your existing identity mapping to the new email.
- **`terraform destroy` is GCP-only** - existing JFrog OIDC resources are not removed. You must delete or update them
  manually in JFrog if needed.
- **Drift is your responsibility** - Terraform will not detect or fix changes made to the JFrog OIDC configuration
  outside this module.

### Switching between modes

| Transition | Guidance |
| --- | --- |
| `false` → `true` | Set `create_jfrog_oidc = true`, provide `jfrog_user` and admin token. If a provider/mapping with the same name already exists, import them or rename/remove the existing resources first to avoid API conflicts. |
| `true` → `false` | Set `create_jfrog_oidc = false` before destroy if you want to keep JFrog OIDC resources. Otherwise `terraform destroy` deletes the Terraform-managed provider and mapping. |

## Outputs

```bash
terraform output function_service_account_email
terraform output default_audience
terraform output jfrog_token_expires_in
terraform output create_jfrog_oidc
```

| Output | Use |
| -------- | ----- |
| `function_service_account_email` | JFrog identity mapping `email` claim |
| `default_audience` | JFrog identity mapping `aud` claim (when `audience` is unset) |
| `configured_audience` | Custom `aud` claim if `audience` variable was set |
| `jfrog_token_expires_in` | Recommended `token_spec.expires_in` for the identity mapping |
| `create_jfrog_oidc` | Whether JFrog OIDC is managed by this Terraform module |
| `secret_resource_name` | Full secret resource path |
| `project_number` | Project number for identity mapping |
| `cloud_function_name` | Deployed function name |
| `create_cloud_run_example` | Whether the connector + Cloud Run example is managed |
| `connector_repository_id` | Artifact Registry connector repository ID |
| `connector_image` | Image path Cloud Run pulls via the connector |
| `cloud_run_service_url` | Public URL of the Nginx Cloud Run example |
| `jfrog_docker_local_key` | JFrog local Docker repository key |
| `jfrog_docker_remote_key` | JFrog remote Docker Hub repository key |
| `jfrog_docker_virtual_key` | JFrog virtual Docker repository key |

When `create_jfrog_oidc = false`, use these outputs to configure or verify your existing identity mapping:

```bash
FUNCTION_SA=$(terraform output -raw function_service_account_email)
AUDIENCE=$(terraform output -raw default_audience)
EXPIRES_IN=$(terraform output -raw jfrog_token_expires_in)
```

```json
"claims": {
  "iss": "https://accounts.google.com",
  "aud": "<AUDIENCE or configured_audience>",
  "email": "<FUNCTION_SA>"
}
```

If you set the `audience` Terraform variable, use `terraform output -raw configured_audience` instead of
`default_audience`.

## Verify

After apply (and after configuring JFrog OIDC when `create_jfrog_oidc = false`), schedule the first rotation or wait for
`next_rotation_time` (default ~6 minutes after plan). See [Setting
`NEXT_ROTATION_TIME`](manual-setup.md#setting-next_rotation_time):

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

## Optional: Artifact Registry connector and Cloud Run example

Set `create_cloud_run_example = true` to provision the same optional path documented in
[Manual setup](manual-setup.md#optional-create-a-google-artifact-registry-connector-repository):

1. JFrog Docker **local** (`jfrog_docker_local_key`), **remote** to Docker Hub (`jfrog_docker_remote_key`), and
   **virtual** (`jfrog_docker_virtual_key`) repositories - skip creation with `create_jfrog_docker_repos = false`
   when reusing existing keys
2. Artifact Registry **connector** repository (`connector_repository_id`) pointing at
   `https://<jfrog_host>/<virtual_key>`, authenticated with `jfrog_user` and Secret Manager
   `versions/latest` ([`no_cache` connector mode](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository))
3. Public Cloud Run service pulling `<image_name>:<image_tag>` (defaults `nginx:latest`) through the connector on
   port 80 - Artifactory resolves the image from Docker Hub via the remote repository (no local image push)

Apply order when the example is enabled:

1. Provision the rotator (secret, function, OIDC, IAM) and schedule the first rotation (~6 minutes after plan by
   default).
2. `null_resource.wait_for_first_rotation` runs
   [`scripts/wait_for_first_rotation.sh`](../terraform-example/scripts/wait_for_first_rotation.sh), which counts down
   360 seconds (printing reason and seconds left) and confirms `versions/latest` is no longer the bootstrap
   placeholder (exits immediately if already rotated). Requires `gcloud` on the machine running `terraform apply`.
3. Create the Artifact Registry connector and Cloud Run service only after that check succeeds.

If `prev_secret_action` is `DESTROY` while the example is enabled, Terraform sets the function's `PREV_SECRET_ACTION`
to `KEEP` instead. Destroying the Terraform-managed bootstrap version would recreate it as `versions/latest` on the
next apply and break connector pulls with `401: Unauthorized error returned by the external repository`.

Requires `hashicorp/google` **7.43.0+** for `no_cache` (pinned in
[`providers.tf`](../terraform-example/providers.tf); `google-beta` is pinned to **7.42.0** until a matching
beta release is published).

Verify with:

```bash
terraform output -raw cloud_run_service_url
curl -sS -o /dev/null -w "%{http_code}\n" "$(terraform output -raw cloud_run_service_url)"
```

> **Note:** Some organizations deny `allUsers` on Cloud Run. If public access fails, remove or adjust the
> `google_cloud_run_v2_service_iam_member.nginx_public` binding.

## Cleanup

When `create_jfrog_oidc = true`, `terraform destroy` removes the JFrog OIDC provider and identity mapping along with GCP
resources.

When `create_jfrog_oidc = false`, only GCP resources are destroyed; JFrog OIDC configuration remains.

When `create_cloud_run_example = true` and `create_jfrog_docker_repos = true`, destroy also removes the managed JFrog
Docker local, remote, and virtual repositories. Reused repos (`create_jfrog_docker_repos = false`) are left in place.

```bash
cd terraform-example
terraform destroy
```
