FROM postgres:17

# Install pgAgent from source or package
RUN apt-get update && \
    apt-get install -y pgagent && \
    rm -rf /var/lib/apt/lists/*

# # Copy entrypoint.sh startup script and make it executable
# COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# RUN chmod +x /usr/local/bin/entrypoint.sh

# Copy pre-created .pgpass file from build context
COPY ./pgagent.pgpass /root/.pgpass
RUN chmod 600 /root/.pgpass

#ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

