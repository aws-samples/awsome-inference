#!/bin/bash

kubectl create secret generic aws-creds --from-literal=AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID --from-literal=AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY --from-literal=AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN