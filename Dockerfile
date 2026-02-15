FROM debian:trixie
ARG APT_PROXY=
ARG PIP_INDEX_URL=
ARG PIP_TRUSTED_HOST=
RUN groupadd -g 900 postgres && \
    useradd -u 900 -g 900 -m -d /var/lib/postgresql -s /bin/bash postgres && \
    passwd -l postgres
RUN test -z "$APT_PROXY" || (echo "Acquire::http::Proxy \"$APT_PROXY\";" > /etc/apt/apt.conf.d/proxy.conf)
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get install -y sudo curl python3-pip python3-dev python3-venv build-essential libpq-dev \
    libmagic1 nginx chromium chromium-driver firefox-esr fonts-noto unifont virtualenv npm && \
    apt-get clean autoclean && \
    apt-get autoremove --yes && \
    rm -rf /var/lib/cache /var/lib/log /usr/share/doc /usr/share/man
RUN curl -L https://github.com/mozilla/geckodriver/releases/download/v0.36.0/geckodriver-v0.36.0-linux64.tar.gz | tar -C /usr/local/bin -x -v -z -f -
RUN test -z "$APT_PROXY" || rm /etc/apt/apt.conf.d/proxy.conf
ARG PIP_INDEX_URL=
ARG PIP_TRUSTED_HOST=
RUN mkdir /root/sosse
WORKDIR /root/sosse
ADD requirements.txt .
ADD pyproject.toml .
ADD MANIFEST.in .
ADD Makefile .
ADD package.json .
ADD swagger-initializer.js .
ADD README.md .
ADD se/ se/
ADD sosse/ sosse/
RUN apt-get update && apt-get install -y postgresql jq git make
RUN cd /root && git clone https://gitlab.com/biolds1/sosse-plugins && \
    cd /root/sosse-plugins && \
    make install-all && \
    apt-get clean autoclean && \
    apt-get autoremove --yes && \
    rm -rf /var/lib/cache /var/lib/log /usr/share/doc /usr/share/man
RUN cd /root/sosse-plugins && \
    make generate-plugins-json && \
    mv plugins.json /root/sosse/sosse/mime_plugins.json
RUN make install_js_deps
RUN virtualenv /venv
RUN /venv/bin/pip install ./ && /venv/bin/pip install uwsgi && /venv/bin/pip cache purge
ADD debian/sosse.conf /etc/nginx/sites-enabled/default
RUN mkdir -p /etc/sosse/ /etc/sosse_src/ /var/log/sosse /var/log/uwsgi /var/www/.cache /var/www/.mozilla
ADD debian/uwsgi.* /etc/sosse_src/
RUN chown -R root:www-data /etc/sosse /etc/sosse_src && chmod 750 /etc/sosse_src/ && chmod 640 /etc/sosse_src/*
RUN chown www-data:www-data /var/log/sosse /var/www/.cache /var/www/.mozilla
ADD docker/run.sh docker/pg_run.sh /
RUN chmod 755 /run.sh /pg_run.sh

WORKDIR /
USER postgres
RUN /etc/init.d/postgresql start && \
    (until pg_isready; do sleep 1; done) && \
    psql --command "CREATE USER sosse WITH PASSWORD 'sosse';" && \
    createdb -O sosse sosse && \
    /etc/init.d/postgresql stop && \
    tar -c -p -C / -f /tmp/postgres_sosse.tar.gz /var/lib/postgresql

USER root

# PostgreSQL from Bookworm for upgrade steps
ADD docker/pip-release/bookworm.sources /etc/apt/sources.list.d/
RUN apt-get update && apt-get install -y postgresql-15 && \
    apt-get clean autoclean && \
    apt-get autoremove --yes && \
    rm -rf /var/lib/cache /var/lib/log /usr/share/doc /usr/share/man
RUN mkdir -p /etc/postgresql/15/main/
ADD docker/pip-release/postgresql.conf.bookworm /etc/postgresql/15/main/postgresql.conf
RUN echo 'local   all             postgres                                peer' > /etc/postgresql/15/main/pg_hba.conf
RUN echo 'auto' > /etc/postgresql/15/main/start.conf

CMD ["/usr/bin/bash", "/pg_run.sh"]
