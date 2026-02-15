FROM debian:trixie
ARG APT_PROXY=
ARG PIP_INDEX_URL=
ARG PIP_TRUSTED_HOST=

# Set up postgres user and install system dependencies
RUN groupadd -g 900 postgres && \
    useradd -u 900 -g 900 -m -d /var/lib/postgresql -s /bin/bash postgres && \
    passwd -l postgres && \
    test -z "$APT_PROXY" || (echo "Acquire::http::Proxy \"$APT_PROXY\";" > /etc/apt/apt.conf.d/proxy.conf) && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y sudo curl python3-pip python3-dev python3-venv build-essential libpq-dev \
        libmagic1 nginx chromium chromium-driver firefox-esr fonts-noto unifont virtualenv npm \
        postgresql jq git make && \
    curl -L https://github.com/mozilla/geckodriver/releases/download/v0.36.0/geckodriver-v0.36.0-linux64.tar.gz | tar -C /usr/local/bin -x -v -z -f - && \
    apt-get clean autoclean && \
    apt-get autoremove --yes && \
    rm -rf /var/lib/cache /var/lib/log /usr/share/doc /usr/share/man && \
    test -z "$APT_PROXY" || rm /etc/apt/apt.conf.d/proxy.conf

# Copy application files
WORKDIR /root/sosse
COPY requirements.txt pyproject.toml MANIFEST.in Makefile package.json swagger-initializer.js README.md ./
COPY se/ se/
COPY sosse/ sosse/
# Install sosse-plugins and build application
RUN cd /root && git clone https://gitlab.com/biolds1/sosse-plugins && \
    cd /root/sosse-plugins && \
    make install-all && \
    make generate-plugins-json && \
    mv plugins.json /root/sosse/sosse/mime_plugins.json && \
    apt-get clean autoclean && \
    apt-get autoremove --yes && \
    rm -rf /var/lib/cache /var/lib/log /usr/share/doc /usr/share/man

# Install JS dependencies and Python packages
RUN make install_js_deps && \
    virtualenv /venv && \
    /venv/bin/pip install ./ && \
    /venv/bin/pip install uwsgi && \
    /venv/bin/pip cache purge

# Configure nginx and directories
RUN mkdir -p /etc/sosse/ /etc/sosse_src/ /var/log/sosse /var/log/uwsgi /var/www/.cache /var/www/.mozilla
COPY debian/sosse.conf /etc/nginx/sites-enabled/default
COPY debian/uwsgi.* /etc/sosse_src/
RUN chown -R root:www-data /etc/sosse /etc/sosse_src && \
    chmod 750 /etc/sosse_src/ && \
    chmod 640 /etc/sosse_src/* && \
    chown www-data:www-data /var/log/sosse /var/www/.cache /var/www/.mozilla

# Copy and set up runtime scripts
COPY docker/run.sh docker/pg_run.sh /
RUN chmod 755 /run.sh /pg_run.sh

# Set up PostgreSQL database as postgres user
WORKDIR /
USER postgres
RUN /etc/init.d/postgresql start && \
    (until pg_isready; do sleep 1; done) && \
    psql --command "CREATE USER sosse WITH PASSWORD 'sosse';" && \
    createdb -O sosse sosse && \
    /etc/init.d/postgresql stop && \
    tar -c -p -C / -f /tmp/postgres_sosse.tar.gz /var/lib/postgresql

# Install PostgreSQL 15 from Bookworm for upgrade steps
USER root
COPY docker/pip-release/bookworm.sources /etc/apt/sources.list.d/
RUN apt-get update && \
    apt-get install -y postgresql-15 && \
    apt-get clean autoclean && \
    apt-get autoremove --yes && \
    rm -rf /var/lib/cache /var/lib/log /usr/share/doc /usr/share/man && \
    mkdir -p /etc/postgresql/15/main/ && \
    echo 'local   all             postgres                                peer' > /etc/postgresql/15/main/pg_hba.conf && \
    echo 'auto' > /etc/postgresql/15/main/start.conf
COPY docker/pip-release/postgresql.conf.bookworm /etc/postgresql/15/main/postgresql.conf

CMD ["/usr/bin/bash", "/pg_run.sh"]
