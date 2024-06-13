FROM postgres:14


RUN apt-get update && apt-get install -y \
    ca-certificates \
    wget \
    gnupg \
    curl \
    gnupg2

RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list'


RUN apt update
RUN apt upgrade

RUN apt-get install -y \
    postgis \
    postgresql-14-postgis-3 \
    postgresql-14-postgis-scripts \
    postgresql-contrib-14 \
    && rm -rf /var/lib/apt/lists/*
