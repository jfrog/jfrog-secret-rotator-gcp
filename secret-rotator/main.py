# (c) JFrog Ltd. (2026)

"""Cloud Function handler for JFrog secret rotation via GCP Secret Manager."""

import base64
import json
import os

import google.auth.transport.requests
import google.oauth2.id_token
import requests
from google.cloud import secretmanager


def get_oidc_token(audience: str) -> str:
    request = google.auth.transport.requests.Request()
    return google.oauth2.id_token.fetch_id_token(request, audience)


def exchange_oidc_tokens(
    id_token: str,
    jfrog_host: str,
    provider_name: str,
    audience: str,
    debug: bool,
) -> dict:
    url = f"https://{jfrog_host}/access/api/v1/oidc/token"
    payload = {
        "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
        "subject_token": id_token,
        "provider_type": "Generic OpenID Connect",
        "provider_name": provider_name,
        "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
        "audience": audience,
    }
    response = requests.post(
        url,
        headers={"content-type": "application/json"},
        json=payload,
        timeout=30,
    )
    if debug:
        print(f"JFrog oidc exchange response status code: {response.status_code}")
    return response.json()


def rotate_secret_handler(event, context):
    print(f"rotate_secret_handler>>> Received event: {event}")

    event_type = event["attributes"]["eventType"]
    pubsub_message = json.loads(base64.b64decode(event["data"]).decode("utf-8"))
    secret_name = pubsub_message["name"]

    print(f"Event type: {event_type}")
    if event_type != "SECRET_ROTATE":
        print(
            f"rotate_secret_handler: Event {event_type} for secret {secret_name} "
            "is not SECRET_ROTATE, skipping token exchange"
        )
        return

    print(f"Received rotation event: {pubsub_message} for secret {secret_name}")

    jfrog_debug = os.environ.get("JFROG_DEBUG")
    jfrog_host = os.environ.get("JFROG_HOST")
    audience = os.environ.get("AUDIENCE") or secret_name
    provider_name = os.environ.get("PROVIDER_NAME")
    prev_secret_action = os.environ.get("PREV_SECRET_ACTION", "DESTROY")

    debug = (jfrog_debug or "").lower() in ("true", "1")
    print(f"JFROG_DEBUG: {jfrog_debug}")
    if debug:
        print(f"JFROG_HOST: {jfrog_host}")
        print(f"AUDIENCE: {audience}")
        print(f"PROVIDER_NAME: {provider_name}")
        print(f"PREV_SECRET_ACTION: {prev_secret_action}")

    token = get_oidc_token(audience)
    if debug:
        payload_start = token.find(".") + 1
        payload_end = token.rfind(".")
        print(f"OIDC token payload: {token[payload_start:payload_end]}")

    exchange_response = exchange_oidc_tokens(token, jfrog_host, provider_name, audience, debug)

    if "access_token" not in exchange_response:
        print(f"ERROR in JFrog exchange response: {exchange_response}")
        return

    access_token = exchange_response["access_token"]
    if debug:
        username = exchange_response.get("username", "")
        print(f"JFrog exchange response: Username: {username}")

    client = secretmanager.SecretManagerServiceClient()
    prev_secret_version = None
    if prev_secret_action != "KEEP":
        try:
            prev_secret_version = client.get_secret_version(request={"name": f"{secret_name}/versions/latest"})
            if debug:
                print(f"Previous secret version: {prev_secret_version.name}")
        except Exception as exc:
            print(
                f"ERROR in getting previous secret version: {exc}, "
                "this is not cancelling the rotation, please destroy old version manually"
            )

    new_secret_version = client.add_secret_version(
        request={
            "parent": secret_name,
            "payload": {"data": access_token.encode("utf-8")},
        }
    )
    if debug:
        print(f"New secret version: {new_secret_version.name}")

    try:
        if (
            prev_secret_action != "KEEP"
            and prev_secret_version is not None
            and new_secret_version.state == secretmanager.SecretVersion.State.ENABLED
            and new_secret_version.name != prev_secret_version.name
        ):
            if prev_secret_action == "DESTROY":
                client.destroy_secret_version(request={"name": prev_secret_version.name})
                if debug:
                    print(f"Destroyed previous secret version: {prev_secret_version.name}")
            elif prev_secret_action == "DISABLE":
                client.disable_secret_version(request={"name": prev_secret_version.name})
                if debug:
                    print(f"Disabled previous secret version: {prev_secret_version.name}")
            else:
                print(
                    "Unknown previous secret handling value, allowed values are: "
                    "KEEP, DESTROY, DISABLE, did not manage previous version, "
                    "please handle it manually"
                )
    except Exception as exc:
        print(
            f"ERROR in managing previous secret version: {exc}, "
            "this is not cancelling the rotation, please manage old version manually"
        )

    print(f"rotate_secret_handler: Successfully rotated secret: {secret_name}")
