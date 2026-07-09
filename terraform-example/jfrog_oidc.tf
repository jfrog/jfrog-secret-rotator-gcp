resource "platform_oidc_configuration" "gcp" {
  count = var.create_jfrog_oidc ? 1 : 0

  name              = var.provider_name
  description       = "OIDC provider for GCP Secret rotation"
  issuer_url        = "https://accounts.google.com"
  provider_type     = "generic"
  use_default_proxy = false
}

resource "platform_oidc_identity_mapping" "rotator" {
  count = var.create_jfrog_oidc ? 1 : 0

  name          = coalesce(var.oidc_mapping_name, var.provider_name)
  description   = "GCP Secret rotation OIDC identity mapping"
  provider_name = platform_oidc_configuration.gcp[0].name
  priority      = var.oidc_mapping_priority

  claims_json = jsonencode({
    iss   = "https://accounts.google.com"
    aud   = local.oidc_audience
    email = google_service_account.rotator.email
  })

  token_spec = {
    username   = var.jfrog_user
    scope      = "applied-permissions/user"
    audience   = "*@*"
    expires_in = local.jfrog_token_expires_in
  }

  depends_on = [
    google_service_account.rotator,
    google_secret_manager_secret.jfrog_token,
    platform_oidc_configuration.gcp,
  ]
}
