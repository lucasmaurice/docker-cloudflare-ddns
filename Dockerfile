FROM alpine:latest

RUN apk update
RUN apk add --no-cache bash curl jq

# Clean up
RUN rm -rf /var/cache/apk/*

# Import the script from the host
COPY ./dns_update.sh /dns_update.sh
RUN chown nobody:nobody /dns_update.sh
RUN chmod 555 /dns_update.sh

# Set the container user and group
USER nobody:nobody

# Set the entrypoint to the script
ENTRYPOINT ["bash", "/dns_update.sh"]
