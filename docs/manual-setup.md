# Manual setup (gcloud & REST API)

Step-by-step deployment using `gcloud` and JFrog REST API. For Terraform, see [Terraform setup](terraform-setup.md).

## Prerequisites

Enable the Eventarc and Artifact Registry APIs on the project:

```bash
PROJECT_ID="my-gcp-project"

gcloud services enable eventarc.googleapis.com artifactregistry.googleapis.com --project "$PROJECT_ID"
```

## GCP: Secret Manager service identity

```bash
PROJECT_ID="my-gcp-project"

gcloud beta services identity create --service "secretmanager.googleapis.com" --project "$PROJECT_ID"
```

Save the resulting service account email as `SM_SERVICE_ACCOUNT`.

## GCP: Pub/Sub notifications

Read more: <https://docs.cloud.google.com/secret-manager/docs/event-notifications>

### Create a Pub/Sub topic

```bash
# Set variables
PROJECT_ID="my-gcp-project"
PUBSUB_TOPIC_NAME="my-rotation-topic"
PUBSUB_SUBSCRIPTION_NAME="my-rotation-subscription"
REGION="us-central1"
FUNCTION_NAME="secret-rotation-function-demo"

gcloud pubsub topics create "projects/$PROJECT_ID/topics/$PUBSUB_TOPIC_NAME"

gcloud pubsub topics add-iam-policy-binding "$PUBSUB_TOPIC_NAME" \
  --member "serviceAccount:${SM_SERVICE_ACCOUNT}" \
  --role "roles/pubsub.publisher"
```

### Create a Pub/Sub subscription

```bash
gcloud pubsub subscriptions create "projects/$PROJECT_ID/subscriptions/$PUBSUB_SUBSCRIPTION_NAME" \
  --topic "projects/$PROJECT_ID/topics/$PUBSUB_TOPIC_NAME"
```

## GCP: Create the secret

```bash
# macOS (BSD date)
NEXT_ROTATION_TIME=$(date -u -v+6M +"%Y-%m-%dT%H:%M:%SZ")
# GNU/Linux
# NEXT_ROTATION_TIME=$(date -u -d "+6 minutes" +"%Y-%m-%dT%H:%M:%SZ")
SECRET_NAME=jfrog-token-rotating
ROTATION_PERIOD="36000s"   # e.g. 10 hours - JFrog token expires_in must exceed this

gcloud secrets create "$SECRET_NAME" \
  --topics="projects/$PROJECT_ID/topics/$PUBSUB_TOPIC_NAME" \
  --rotation-period="$ROTATION_PERIOD" \
  --next-rotation-time="$NEXT_ROTATION_TIME"
```

Optional flags:

| Flag | Description |
| ------ | ------------- |
| `--set-annotations` | Custom annotations on the secret |
| `--rotation-period` | Interval between rotation notifications (e.g. `36000s`) - **required** for rotation |
| `--next-rotation-time` | RFC3339 timestamp for the first rotation notification |

The secret is created without a payload in manual setup. With Terraform, the first version is seeded from
`bootstrap_jfrog_token`, or a placeholder when that is unset (see [Bootstrap secret
version](#bootstrap-secret-version)). Otherwise the **first real secret version** is written by the rotation function
when it handles the first `SECRET_ROTATE` event (see [First secret version](#first-secret-version)).

## GCP: Artifact Registry access to the secret

Grant the Artifact Registry service agent `roles/secretmanager.secretAccessor` on the secret so Artifact Registry
Connector mode repositories can read the rotated token:

```bash
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-artifactregistry.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

When creating the Google Artifact Registry Connector mode repository, reference the secret by name (e.g.
`jfrog-token-rotating`). Google Artifact Registry reads the `latest` version, so it picks up new tokens after each
rotation.

## GCP: Cloud Function (Gen2)

### Service account

```bash
# Set variables
FUNCTION_SERVICE_ACCOUNT="jfrog-secret-rotator-sa"
FUNCTION_SERVICE_ACCOUNT_EMAIL="${FUNCTION_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"

# Create the service account
gcloud iam service-accounts create "$FUNCTION_SERVICE_ACCOUNT" \
  --display-name="Secret Rotation Service Account"

# Grant permission to manage secrets and limit the permission to the specific rotated secret name and its versions
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/secretmanager.editor" \
  --condition="expression=resource.name.startsWith(\"projects/$PROJECT_NUMBER/secrets/$SECRET_NAME\"),title=limit to single secret,description=limit permissions to only apply on the rotated secret)"
```

### Deploy function

Run from the repository root and point `--source` at the `secret-rotator` directory:

#### Environment variables

| Variable | Required | Default | Description |
| ---------- | ---------- | --------- | ------------- |
| `JFROG_HOST` | yes | - | JFrog hostname (e.g. `myregistry.jfrog.io`) |
| `PROVIDER_NAME` | yes | - | JFrog OIDC provider name (must match the provider created below) |
| `AUDIENCE` | no | secret resource name | Google OIDC `aud` claim; default format: `projects/<project_number>/secrets/<secret_name>` |
| `PREV_SECRET_ACTION` | no | `DESTROY` | Previous version handling: `KEEP`, `DESTROY`, or `DISABLE` |
| `JFROG_DEBUG` | no | - | Set to `true` or `1` for debug logs (tokens are never logged) |

Terraform variable names use lowercase snake_case (e.g. `jfrog_host` → `JFROG_HOST`).

```bash
# Set variables (omit AUDIENCE to default to the secret resource name at runtime)
JFROG_HOST="myregistry.jfrog.io"
PROVIDER_NAME="gcp-oidc"
PREV_SECRET_ACTION="DESTROY"
JFROG_DEBUG="false"

gcloud functions deploy "$FUNCTION_NAME" \
  --gen2 \
  --runtime=python312 \
  --region="$REGION" \
  --source=secret-rotator \
  --set-env-vars="JFROG_HOST=${JFROG_HOST},PROVIDER_NAME=${PROVIDER_NAME},PREV_SECRET_ACTION=${PREV_SECRET_ACTION},JFROG_DEBUG=${JFROG_DEBUG}" \
  --entry-point=rotate_secret_handler \
  --trigger-topic="$PUBSUB_TOPIC_NAME" \
  --retry \
  --service-account="${FUNCTION_SERVICE_ACCOUNT_EMAIL}"
```

Set `AUDIENCE` only if your JFrog identity mapping uses a fixed audience string instead of the default secret resource
name:

```bash
AUDIENCE="jfrog_user1"   # or projects/${PROJECT_NUMBER}/secrets/${SECRET_NAME}

gcloud functions deploy "$FUNCTION_NAME" \
  --gen2 \
  --region="$REGION" \
  --source=secret-rotator \
  --update-env-vars="AUDIENCE=${AUDIENCE}"
```

### Invoker permissions (Eventarc / Cloud Run)

Gen2 functions run on Cloud Run. Pub/Sub delivers events via an **Eventarc push subscription** that signs an OIDC token
and calls the Cloud Run service. You need **three** IAM bindings:

| Principal | Role | Resource |
| ----------- | ------ | ---------- |
| Eventarc trigger service account | `roles/run.invoker` | Cloud Run service |
| Pub/Sub service agent | `roles/run.invoker` | Cloud Run service |
| Pub/Sub service agent | `roles/iam.serviceAccountTokenCreator` | Function service account |

When you deploy with `--service-account`, that account is used as the **Eventarc trigger identity** (not the Compute
Engine default). Pub/Sub must be allowed to mint OIDC tokens for it, or requests arrive unauthenticated and logs show
`lacks {run.routes.invoke} permission`.

Run **after** the function is deployed:

```bash
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

# Cloud Run service name matches the function name for Gen2
CLOUD_RUN_SERVICE=$(gcloud functions describe "$FUNCTION_NAME" --gen2 --region="$REGION" --format='value(serviceConfig.service)')
CLOUD_RUN_SERVICE="${CLOUD_RUN_SERVICE##*/}"   # strip projects/.../services/ prefix if present

# Eventarc trigger service account (when using --service-account, this is usually the same SA)
TRIGGER_SA=$(gcloud eventarc triggers list --location="$REGION" \
  --format='value(serviceAccount)' --filter="labels.goog-drz-cloudfunctions-id=${FUNCTION_NAME}" | head -1)
TRIGGER_SA="${TRIGGER_SA:-${FUNCTION_SERVICE_ACCOUNT_EMAIL}}"

# 1. Eventarc trigger SA → invoke Cloud Run
gcloud run services add-iam-policy-binding "$CLOUD_RUN_SERVICE" \
  --region="$REGION" \
  --member="serviceAccount:${TRIGGER_SA}" \
  --role="roles/run.invoker"

# 2. Pub/Sub service agent → invoke Cloud Run
gcloud run services add-iam-policy-binding "$CLOUD_RUN_SERVICE" \
  --region="$REGION" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role="roles/run.invoker"

# 3. Pub/Sub service agent → sign OIDC push tokens as the trigger SA
gcloud iam service-accounts add-iam-policy-binding "${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator"
```

Verify bindings:

```bash
gcloud run services get-iam-policy "$CLOUD_RUN_SERVICE" --region="$REGION"
gcloud iam service-accounts get-iam-policy "${FUNCTION_SERVICE_ACCOUNT_EMAIL}"
gcloud eventarc triggers list --location="$REGION" \
  --format="table(name,serviceAccount)" --filter="labels.goog-drz-cloudfunctions-id=${FUNCTION_NAME}"
```

Without step 3, Cloud Run logs show `The request was not authenticated` / `lacks {run.routes.invoke} permission` even
when step 1-2 appear correct.

## JFrog OIDC integration

```bash
# Set variables (PROVIDER_NAME must match the function env var above)
JFROG_HOST="myregistry.jfrog.io"
JFROG_URL="https://${JFROG_HOST}"
JFROG_ADMIN_TOKEN="your-admin-access-token"
JFROG_USER="gcp-user" # This user must exist and have the right permissions on JFrog
PROVIDER_NAME="gcp-oidc"

# Create OIDC provider in JFrog
curl -X POST "${JFROG_URL}/access/api/v1/oidc" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${JFROG_ADMIN_TOKEN}" \
  -d "{
    \"name\": \"${PROVIDER_NAME}\",
    \"issuer_url\": \"https://accounts.google.com/\",
    \"description\": \"OIDC provider for GCP Secret rotation\",
    \"provider_type\": \"Generic OpenID Connect\",
    \"token_issuer\": \"https://accounts.google.com\",
    \"use_default_proxy\": false
  }"
```

### Create identity mapping

The identity mapping tells JFrog how to map Google OIDC tokens to JFrog users.

> **IMPORTANT:** Ensure `expires_in` is longer than your secret rotation period so the latest secret version always has
> a valid JFrog access token

If using multiple mappings, set distinct `priority` values (lower number = higher priority).

Set `JFROG_TOKEN_EXPIRES_IN` to at least 30% longer than `ROTATION_PERIOD` (in seconds). For the default
`ROTATION_PERIOD` of `36000s` (10 hours), use `46800` (13 hours):

```bash
# Must exceed ROTATION_PERIOD - 46800 = 36000s × 1.3
JFROG_TOKEN_EXPIRES_IN=46800
AZP=$(gcloud iam service-accounts describe $FUNCTION_SERVICE_ACCOUNT_EMAIL --project=$PROJECT_ID --format="value(uniqueId)")

curl -X POST "${JFROG_URL}/access/api/v1/oidc/${PROVIDER_NAME}/identity_mappings" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${JFROG_ADMIN_TOKEN}" \
  -d "{
    \"name\": \"${PROVIDER_NAME}\",
    \"description\": \"GCP Secret rotation OIDC identity mapping\",
    \"claims\": {
      \"iss\": \"https://accounts.google.com\",
      \"aud\": \"projects/${PROJECT_NUMBER}/secrets/${SECRET_NAME}\",
      \"azp\": \"${AZP}\",
      \"email\": \"${FUNCTION_SERVICE_ACCOUNT_EMAIL}\"
    },
    \"token_spec\": {
      \"username\": \"${JFROG_USER}\",
      \"scope\": \"applied-permissions/user\",
      \"audience\": \"*@*\",
      \"expires_in\": ${JFROG_TOKEN_EXPIRES_IN}
    },
    \"priority\": 1
  }"
```

## First secret version

The rotation function creates secret versions - you do not put a JFrog token in Secret Manager manually. After the
secret, function, IAM bindings, and JFrog OIDC integration are in place, trigger the first rotation and confirm a
version was created.

### 1. Trigger the first rotation

Schedule the next rotation at least 5 minutes ahead (6 minutes is used below for margin). Secret Manager publishes a
`SECRET_ROTATE` event at that time, which invokes the Cloud Function:

```bash
NEXT_ROTATION_TIME=$(date -u -v+6M +"%Y-%m-%dT%H:%M:%SZ")   # macOS
# NEXT_ROTATION_TIME=$(date -u -d "+6 minutes" +"%Y-%m-%dT%H:%M:%SZ")   # GNU/Linux

gcloud secrets update "$SECRET_NAME" \
  --next-rotation-time="$NEXT_ROTATION_TIME"
```

Wait until `next_rotation_time` passes, then verify (step 3 below).

Alternatively, if you already set `next_rotation_time` at create time, wait for that scheduled time.

> **Note:** IAM changes (Pub/Sub invoker, Secret Manager publisher) can take a minute or two to propagate. If the
> function is not invoked, wait and trigger again with a fresh `next_rotation_time`.

### 2. Verify the secret version

List versions - you should see at least one `ENABLED` version after a successful run:

```bash
gcloud secrets versions list "$SECRET_NAME"
```

Read the latest value (the JFrog access token):

```bash
gcloud secrets versions access latest --secret="$SECRET_NAME"
```

Check Cloud Function logs for a successful rotation:

```bash
gcloud functions logs read "$FUNCTION_NAME" --gen2 --region="$REGION" --limit=50
```

Look for `Successfully rotated secret` in the logs. If rotation fails, common causes are:

- `PROVIDER_NAME` on the function does not match the JFrog OIDC provider name
- JFrog identity mapping `aud` / `email or azp` claims do not match the function service account and audience
- Pub/Sub or Eventarc invoker permissions missing on the Cloud Run service backing the function - see [Invoker
  permissions](#invoker-permissions-eventarc--cloud-run). Cloud Run logs showing `lacks {run.routes.invoke} permission`
  usually mean the **function service account** is missing `run.invoker`, or Pub/Sub is missing
  `serviceAccountTokenCreator` on that SA.

### Bootstrap secret version

Terraform seeds the first Secret Manager version with `bootstrap_jfrog_token`, or the placeholder `dummy-token` when
that is unset. Note that the placeholder is **not** a valid token - Google Artifact Registry and other consumers will
fail until the first rotation completes. To have a working token immediately, either wait for the first rotation to
complete or pre-set
`bootstrap_jfrog_token` with a valid initial JFrog access token. For manual setup, add a real JFrog access token:

```bash
echo -n "$JFROG_ACCESS_TOKEN" | gcloud secrets versions add "$SECRET_NAME" --data-file=-
```

The next successful rotation adds a new version with the OIDC-exchanged access token (previous version is kept,
disabled, or destroyed per `PREV_SECRET_ACTION`).

## Helper utilities

Update function env vars (run from the repository root):

```bash
gcloud functions deploy "$FUNCTION_NAME" \
  --gen2 \
  --region="$REGION" \
  --source=secret-rotator \
  --update-env-vars="JFROG_HOST=${JFROG_HOST},PROVIDER_NAME=${PROVIDER_NAME},PREV_SECRET_ACTION=${PREV_SECRET_ACTION},JFROG_DEBUG=${JFROG_DEBUG}"
```

To clear a previously set empty `AUDIENCE` and use the runtime default:

```bash
gcloud functions deploy "$FUNCTION_NAME" \
  --gen2 \
  --region="$REGION" \
  --source=secret-rotator \
  --remove-env-vars=AUDIENCE
```

Get the latest secret version value:

```bash
gcloud secrets versions access latest --secret="$SECRET_NAME"
```

## Token expiry vs rotation period

Set JFrog OIDC token expiration (`token_spec.expires_in`, in **seconds**) to expire **after** the secret rotation period
so consumers do not hit an expired JFrog token before the next rotation.

| `rotation_period` / `ROTATION_PERIOD` | Minimum `expires_in` | Recommended `expires_in` (30% margin) |
| ---------------------------------------- | ---------------------- | ---------------------------------------- |
| `3600s` (1 hour) | `3601` | `4680` |
| `36000s` (10 hours) | `36001` | `46800` |

A good rule of thumb is to set `expires_in` to at least **30% longer** than the rotation period.

## Previous secret versions

Each rotation adds a new Secret Manager version. The rotation function can clean up the previous version via
`PREV_SECRET_ACTION` (default: `DESTROY`):

| Value | Behavior | When to use |
| ------- | ---------- | ------------- |
| `KEEP` | Previous version stays **enabled** | Useful for rollback or debugging; versions accumulate over time. |
| `DESTROY` | Previous version is **permanently deleted** | Default. Recommended for production. Google Artifact Registry reads `latest`, so old versions are not needed. Reduces secret sprawl and exposure window. |
| `DISABLE` | Previous version is **disabled** (not readable, not deleted) | Middle ground: blocks access but retains metadata for audit. |

With `KEEP`, old versions remain readable by anyone with `secretAccessor`. To remove them manually:

```bash
gcloud secrets versions destroy VERSION_ID --secret="$SECRET_NAME"
```

For Google Artifact Registry Connector mode repositories, **`DESTROY` is usually the right choice** - consumers always
read the latest version and do not benefit from keeping old tokens.

## Optional: Create a Google Artifact Registry connector repository

After all resources are created and the first rotation succeeds, optionally create a
[Google Artifact Registry connector repository](https://docs.cloud.google.com/artifact-registry/docs/repositories/connector-repo)
that proxies a JFrog Docker virtual repository (backed by a local Docker repository), push a tagged Nginx image into
JFrog, then deploy a public Cloud Run service that pulls that image through the connector.

Connector repositories are a **Preview** feature. You need Artifact Registry Admin on the project and
Secret Manager access for the rotated secret (already granted in
[Artifact Registry access to the secret](#gcp-artifact-registry-access-to-the-secret)). Docker must be available
locally to pull, retag, and push the example image.

> **IMPORTANT:** Reference the Secret Manager secret version as `latest` so Google Artifact Registry always
> uses the newest JFrog token after each rotation.

### Prepare Variables

Reuse values from earlier steps where possible. Override repository names if you already have JFrog Docker
repositories to use as the connector upstream - then skip the matching create commands below.

```bash
# Reuse from earlier sections (adjust if needed)
PROJECT_ID="my-gcp-project"
REGION="us-central1"
SECRET_NAME="jfrog-token-rotating"
JFROG_HOST="myregistry.jfrog.io"
JFROG_URL="https://${JFROG_HOST}"
JFROG_ADMIN_TOKEN="your-admin-access-token"
JFROG_USER="gcp-user"   # must be able to push to local and pull from the virtual Docker repository

# Overridable - set to existing repo keys and skip create if they already exist
JFROG_DOCKER_LOCAL="connector-docker-local"
JFROG_DOCKER_VIRTUAL="connector-docker"

# Artifact Registry connector and Cloud Run example
CONNECTOR_REPOSITORY="jfrog-docker-connector"
CLOUD_RUN_SERVICE="nginx-via-jfrog-connector"
NGINX_SOURCE_IMAGE="nginx:latest"
NGINX_TAG="jfrog-local"
NGINX_IMAGE="nginx:${NGINX_TAG}"
```

### Set up the connector repository

Create the JFrog upstream, push the example image, and wire Artifact Registry to that secret-backed connector.

#### 1. Create JFrog Docker local and virtual repositories

Skip either `curl` if the repository already exists and you pointed the variables at it.

Create a local Docker repository:

```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/${JFROG_DOCKER_LOCAL}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${JFROG_ADMIN_TOKEN}" \
  -d "{
    \"key\": \"${JFROG_DOCKER_LOCAL}\",
    \"rclass\": \"local\",
    \"packageType\": \"docker\",
    \"description\": \"Local Docker repo for Artifact Registry connector example\",
    \"dockerApiVersion\": \"V2\"
  }"
```

Create a virtual Docker repository that fronts the local repository (and accepts deploys into it):

```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/${JFROG_DOCKER_VIRTUAL}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${JFROG_ADMIN_TOKEN}" \
  -d "{
    \"key\": \"${JFROG_DOCKER_VIRTUAL}\",
    \"rclass\": \"virtual\",
    \"packageType\": \"docker\",
    \"description\": \"Virtual Docker repo for Artifact Registry connector example\",
    \"repositories\": [\"${JFROG_DOCKER_LOCAL}\"],
    \"defaultDeploymentRepo\": \"${JFROG_DOCKER_LOCAL}\"
  }"
```

Upstream URL for the Artifact Registry connector:

```bash
JFROG_UPSTREAM_URL="${JFROG_URL}/${JFROG_DOCKER_VIRTUAL}"
echo "$JFROG_UPSTREAM_URL"
```

Ensure `JFROG_USER` can push to `${JFROG_DOCKER_LOCAL}` and pull from `${JFROG_DOCKER_VIRTUAL}`.

#### 2. Pull, tag, and push Nginx to JFrog

Pull `nginx:latest` from Docker Hub on your machine, retag it for the JFrog local repository with the special tag
`${NGINX_TAG}`, and push it to Artifactory.

Use `--platform linux/amd64` so the image runs on Cloud Run (amd64). On Apple Silicon (`arm64`), a default
`docker pull` stores an arm64 image; Cloud Run then fails with `exec format error` / "failed to load
/docker-entrypoint.sh".

```bash
docker pull --platform linux/amd64 "$NGINX_SOURCE_IMAGE"

JFROG_NGINX_IMAGE="${JFROG_HOST}/${JFROG_DOCKER_LOCAL}/${NGINX_IMAGE}"
docker tag "$NGINX_SOURCE_IMAGE" "$JFROG_NGINX_IMAGE"

echo "$JFROG_ADMIN_TOKEN" | docker login "$JFROG_HOST" -u "$JFROG_USER" --password-stdin
docker push "$JFROG_NGINX_IMAGE"
```

Confirm the image is present (optional):

```bash
curl -sS -H "Authorization: Bearer ${JFROG_ADMIN_TOKEN}" \
  "${JFROG_URL}/artifactory/api/docker/${JFROG_DOCKER_LOCAL}/v2/nginx/tags/list"
```

#### 3. Create the Artifact Registry connector repository

Confirm a usable JFrog token is in Secret Manager (`gcloud secrets versions access latest --secret="$SECRET_NAME"`)
before creating the connector. Create the connector with basic auth against that secret:

```bash
gcloud artifacts repositories create "$CONNECTOR_REPOSITORY" \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --description="Connector to JFrog ${JFROG_DOCKER_VIRTUAL}" \
  --repository-format=docker \
  --mode=connector-repository \
  --remote-docker-repo="$JFROG_UPSTREAM_URL" \
  --remote-username="$JFROG_USER" \
  --remote-password-secret-version="projects/${PROJECT_ID}/secrets/${SECRET_NAME}/versions/latest"
```

Image path for consumers (Cloud Run below) - same image name and tag pushed to JFrog, resolved via the connector:

```bash
CONNECTOR_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${CONNECTOR_REPOSITORY}/${NGINX_IMAGE}"
echo "$CONNECTOR_IMAGE"
```

### Test with Cloud Run

Deploy Nginx from the connector image and confirm Cloud Run can pull through Artifact Registry into JFrog.

#### 1. Deploy Nginx on Cloud Run via the connector

Pulls go through Artifact Registry -> JFrog virtual -> JFrog local (`nginx:jfrog-local`). Set container port to `80`
(Nginx listens on 80; Cloud Run defaults to 8080). Allow unauthenticated access for this example:

```bash
gcloud run deploy "$CLOUD_RUN_SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --image="$CONNECTOR_IMAGE" \
  --port=80 \
  --allow-unauthenticated
```

> **Note:** Some organizations deny `allUsers` on Cloud Run (`roles/run.invoker`). If deploy fails on public access,
> omit `--allow-unauthenticated` and invoke the service with an identity that has `roles/run.invoker`.

#### 2. Print and verify the service URL

```bash
CLOUD_RUN_URL=$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format='value(status.url)')
echo "Cloud Run Nginx URL: ${CLOUD_RUN_URL}"

curl -sS -o /dev/null -w "%{http_code}\n" "$CLOUD_RUN_URL"
```

A successful pull path returns HTTP `200` and the default Nginx welcome page at `$CLOUD_RUN_URL`.

## Teardown

Run these commands to remove GCP resources created by the manual setup above. Set variables to the values you used when
creating resources.

```bash
# Variables - adjust to match your deployment
PROJECT_ID="my-gcp-project"
REGION="us-central1"
FUNCTION_NAME="secret-rotation-function-demo"
SECRET_NAME="jfrog-token-rotating"
PUBSUB_TOPIC_NAME="my-rotation-topic"
PUBSUB_SUBSCRIPTION_NAME="my-rotation-subscription"
FUNCTION_SERVICE_ACCOUNT="jfrog-secret-rotator-sa"
FUNCTION_SERVICE_ACCOUNT_EMAIL="${FUNCTION_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"

# Optional connector / Cloud Run example (skip if you did not create them)
CONNECTOR_REPOSITORY="jfrog-docker-connector"
CLOUD_RUN_SERVICE="nginx-via-jfrog-connector"

# Optional JFrog repos from the connector example (only delete if this guide created them)
JFROG_HOST="myregistry.jfrog.io"
JFROG_URL="https://${JFROG_HOST}"
JFROG_ADMIN_TOKEN="your-admin-access-token"
JFROG_DOCKER_LOCAL="connector-docker-local"
JFROG_DOCKER_VIRTUAL="connector-docker"

# 0a. Optional: delete Cloud Run Nginx example
gcloud run services delete "$CLOUD_RUN_SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --quiet

# 0b. Optional: delete Artifact Registry connector repository
gcloud artifacts repositories delete "$CONNECTOR_REPOSITORY" \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --quiet

# 1. Delete Cloud Function (Gen2) - also removes the Eventarc trigger and Cloud Run service
gcloud functions delete "$FUNCTION_NAME" --gen2 --region="$REGION" --quiet

# 2. Delete any orphaned Eventarc triggers (if step 1 left any behind)
for trigger in $(gcloud eventarc triggers list --location="$REGION" --format='value(name)' 2>/dev/null); do
  if [[ "$trigger" == *"$FUNCTION_NAME"* ]]; then
    gcloud eventarc triggers delete "$trigger" --location="$REGION" --quiet
  fi
done

# 3. Delete Secret Manager secret (all versions)
gcloud secrets delete "$SECRET_NAME" --quiet

# 4. Delete Pub/Sub subscription
gcloud pubsub subscriptions delete "$PUBSUB_SUBSCRIPTION_NAME" --quiet

# 5. Delete Pub/Sub topic
gcloud pubsub topics delete "$PUBSUB_TOPIC_NAME" --quiet

# 6. Remove project IAM binding for the function service account
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/secretmanager.editor" \
  --quiet 2>/dev/null || true

# 7. Delete the function service account
gcloud iam service-accounts delete "$FUNCTION_SERVICE_ACCOUNT_EMAIL" --quiet
```

### Optional: delete JFrog Docker repositories from this example

Only run these if this guide created the repositories. **Do not** delete reused existing repositories.

```bash
# Virtual first, then local
curl -X DELETE "${JFROG_URL}/artifactory/api/repositories/${JFROG_DOCKER_VIRTUAL}" \
  -H "Authorization: Bearer ${JFROG_ADMIN_TOKEN}"

curl -X DELETE "${JFROG_URL}/artifactory/api/repositories/${JFROG_DOCKER_LOCAL}" \
  -H "Authorization: Bearer ${JFROG_ADMIN_TOKEN}"
```

JFrog OIDC provider and identity mapping are not removed by these commands - delete those manually in JFrog if needed.

The Secret Manager service identity (`service-PROJECT_NUMBER@gcp-sa-secretmanager.iam.gserviceaccount.com`) is a
project-level resource and is intentionally left in place.
