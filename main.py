# Import the Secret Manager client library.
import os
import base64
import json
import requests
from google.cloud import secretmanager
import google.oauth2.id_token
import google.auth.transport.requests


def get_oidc_token(audience):
    request = google.auth.transport.requests.Request()   
    id_token = google.oauth2.id_token.fetch_id_token(request, audience)
    return id_token

def exchange_oidc_tokens(id_token, jfrog_host, provider_name, audience, debug):
    # exchnage google oidc token with jfrog access token using the below endpoint
    # curl --location 'https://jfrog_host/access/api/v1/oidc/token' \
    # --header 'content-type: application/json' \
    # --header 'subject_token: ey...' \
    # --data '{
    # "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
    # "subject_token": "ey...",
    # "provider_type": "Generic OpenID Connect",
    # "provider_name": "jfrog-oidc-providername",
    # "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
    # "audience": "audience"
    # }'
    url = f"https://{jfrog_host}/access/api/v1/oidc/token"
    headers = {
        "content-type": "application/json"
    }
    data = {
        "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
        "subject_token": f"{id_token}",
        "provider_type": "Generic OpenID Connect",
        "provider_name": f"{provider_name}",
        "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
        "audience": f"{audience}"
    }
    response = requests.post(url, headers=headers, data=json.dumps(data))
    if debug:
        print(f"JFrog oidc exchange response status code: {response.status_code}")
    return response.json()

def rotate_secret_handler(event, context):
    # Secret Manager sends the secret name in the message data
    print(f"rotate_secret_handler>>> Received event: {event}")
    event_type = event["attributes"]["eventType"]
    # pubsub_message format: projects/[PROJECT_NUMBER]/secrets/[SECRET_ID]
    pubsub_message = json.loads(base64.b64decode(event['data']).decode('utf-8'))
    secret_name = pubsub_message["name"]
    print(f"Event type: {event_type}")
    if event_type != "SECRET_ROTATE":
        print(f"rotate_secret_handler: Event {event_type} for secret {secret_name} is not SECRET_ROTATE, skipping token exchange")
        return

    print(f"Received rotation event: {pubsub_message} for secret {secret_name}")
    jfrog_debug = os.environ.get('JFROG_DEBUG')
    jfrog_host = os.environ.get('JFROG_HOST')
    # get audience from env var and default to secret name
    audience = os.environ.get('AUDIENCE', secret_name)
    provider_name = os.environ.get('PROVIDER_NAME')
    prev_secret_action = os.environ.get('PREV_SECRET_ACTION', "KEEP")
    print(f"JFROG_DEBUG: {jfrog_debug}")
    if jfrog_debug == "true" or jfrog_debug == "1":
        debug = True
    if debug:
        print(f"JFROG_HOST: {jfrog_host}")
        print(f"AUDIENCE: {audience}")
        print(f"PROVIDER_NAME: {provider_name}")
        print(f"PREV_SECRET_ACTION: {prev_secret_action}")
        
    token = get_oidc_token(audience)
    if debug:
        # print the middle part of the token between the two . characters
        print(f"OIDC token payload: {token[token.find('.')+1:token.rfind('.')]}")        
    exchange_response = exchange_oidc_tokens(token, jfrog_host, provider_name, audience, debug)
    
    access_token = exchange_response["access_token"]    
    username = exchange_response["username"]
    if debug:
        print(f"JFrog exchange response: Username: {username}")
    else: 
        print(f"ERROR in JFrog exchange response")
    # print(f"Access token: {access_token}")
    # create the new payload with the new access token
    #new_payload = {
     #   "token": access_token,
    #    "username": username
    #}
    # create new version in Secret Manager
    client = secretmanager.SecretManagerServiceClient()
    prev_secret_version = None
    if prev_secret_action != "KEEP":
        try:
            # get the previous secret version
            prev_secret_version = client.get_secret_version(
                request={
                    "name": f"{secret_name}/versions/latest"
                }
            )
            if debug: 
                print(f"Previous secret version: {prev_secret_version.name}")
        except Exception as e:
            print(f"ERROR in getting previous secret version: {e}, this is not cancelling the rotation, please destroy old version manually")
            
    # create a new secret version
    #convert access_token to utf-8
    access_token_utf8 = access_token.encode('utf-8')
    new_secret_version = client.add_secret_version(
        request={
            "parent": secret_name, 
            "payload": {"data": access_token_utf8}
        }
    )
    if debug: 
        print(f"New secret version: {new_secret_version.name}")
    
    # check if the new secret version is enabled and different from the previous secret version
    try:
        if prev_secret_action != "KEEP" and new_secret_version.state == secretmanager.SecretVersion.State.ENABLED and new_secret_version.name != prev_secret_version.name: 
            if prev_secret_action == "DESTROY":
                # destroy the previous secret version
                client.destroy_secret_version(
                    request={
                        "name": prev_secret_version.name
                    }
                )
                if debug: 
                    print(f"Destroyed previous secret version: {prev_secret_version.name}")            
            elif prev_secret_action == "DISABLE":
                # disable the previous secret version
                client.disable_secret_version(
                    request={
                        "name": prev_secret_version.name
                    }
                )
                if debug: 
                    print(f"Disabled previous secret version: {prev_secret_version.name}")
            else:
                print(f"Unknown previous secret handling value, allowed values are: KEEP, DESTROY, DISABLE, did not manage previous version, please handle it manually")
        else:
            print(f"Previous secret version is not enabled, skipping destruction")
        
    except Exception as e:
        print(f"ERROR in managing previous secret version: {e}, this is not cancelling the rotation, please manage old version manually")
        
    print(f"rotate_secret_handler: Successfully rotated secret: {secret_name}")