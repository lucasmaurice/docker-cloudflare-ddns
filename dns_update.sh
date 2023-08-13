#!/bin/bash

# REQUIREMENTS:
# - curl
# - jq

# Required environment variables:
# CF_TOKEN: ------------ Cloudflare API token
# CF_ZONE: ------------- Cloudflare zone ID
# CF_ENTRY: ------------ Cloudflare DNS record ID
# PO_TOKEN: ------------ Pushover API token
# PO_USERKEY: ---------- Pushover user key

# List of remotes that return our public IP address
PUBLIC_IP_PROVIDERS="ipinfo.io/ip icanhazip.com ifconfig.me/ip ipecho.net/plain checkip.amazonaws.com ifconfig.co/ip"
IPS=()

# Try each providers and add the IP to the list if it's a valid IP
for provider in $PUBLIC_IP_PROVIDERS; do
  ip=$(curl -s https://$provider)
  if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IPS+=($ip)
  else
    echo "Invalid IP from $provider: $ip"
  fi
done

# Check that there is at least two IPs
if [ ${#IPS[@]} -lt 2 ]; then
  echo "Not enough public IPs found to be sure - will not update DNS"
  exit 1
fi

# Check that all the IPs are the same
for (( i=1; i<${#IPS[@]}; i++ )); do
  if [ "${IPS[$i]}" != "${IPS[0]}" ]; then
    echo "Public IPs don't match - will not update DNS"
    exit 1
  fi
done

# Check the current DNS record using the cloudflare API
RECORD_RESPONSE=$(curl -sX GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records/$CF_ENTRY" \
     -H "Authorization: Bearer $CF_TOKEN" \
     -H "Content-Type:application/json")

if ! $(echo $RECORD_RESPONSE | jq .success);
then
  echo "Error getting DNS record. See below:"
  echo $RECORD_RESPONSE | jq .errors[].message
  MESSAGE="Error getting DNS record. Errors:
$(echo $CHANGE_RETURN | jq .errors[].message)"
  curl -s https://api.pushover.net/1/messages.json \
    --form-string "token=$PO_TOKEN" \
    --form-string "user=$PO_USERKEY" \
    --form-string "title=Failure reading Cloudflare entries!" \
    --form-string "priority=1"
  exit 1
fi

RECORD_IP=$(echo $RECORD_RESPONSE | jq -r .result.content)

# If the public IP and the DNS record IP are the same, we don't need to do anything
if [ "${IPS[0]}" == "$RECORD_IP" ]; then
  echo "IPs match - no update required"
  exit 0
fi

# Change the DNS record to the new IP using the cloudflare API
CHANGE_RETURN=$(curl -sX PATCH https://api.cloudflare.com/client/v4/zones/$CF_ZONE/dns_records/$CF_ENTRY \
  -H "Authorization: Bearer $CF_TOKEN" \
  --data "{\"content\": \"${IPS[0]}\"}")

echo "Record IP: $RECORD_IP"
echo "Public IP: ${IPS[0]}"

# Send a notification to Pushover
if $(echo $CHANGE_RETURN | jq .success);
then
  echo "DNS updated successfully."
  curl https://api.pushover.net/1/messages.json \
    --form-string "token=$PO_TOKEN" \
    --form-string "user=$PO_USERKEY" \
    --form-string "title=Home public IP updated!" \
    --form-string "priority=-1" \
    --form-string "message=Public IP successfully changed from $RECORD_IP to ${IPS[0]}."
else
  echo "Error updating DNS. See below:"
  echo $CHANGE_RETURN | jq .errors[].message
  MESSAGE="DNS update failed from $RECORD_IP to ${IPS[0]}. Errors:
$(echo $CHANGE_RETURN | jq .errors[].message)"
  curl https://api.pushover.net/1/messages.json \
    --form-string "token=$PO_TOKEN" \
    --form-string "user=$PO_USERKEY" \
    --form-string "title=Home public IP update failed!" \
    --form-string "priority=1" \
    --form-string "message=$MESSAGE"
fi
