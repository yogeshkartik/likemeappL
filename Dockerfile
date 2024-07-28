# For more information, please refer to https://aka.ms/vscode-docker-python
FROM python:3.10-slim

EXPOSE 8000

# Keeps Python from generating .pyc files in the container
ENV PYTHONDONTWRITEBYTECODE=1

# Turns off buffering for easier container logging
ENV PYTHONUNBUFFERED=1

# Install pip requirements
# COPY requirements.txt .
# RUN python -m pip install -r requirements.txt
# postgis \
#     postgresql-14-postgis-3 \
#     postgresql-14-postgis-scripts \
#     postgresql-contrib-14 \
#     && rm -rf /var/lib/apt/lists/*
RUN pip3 install pipenv
RUN apt-get update && apt-get install -y \
    ca-certificates \
    wget \
    gnupg \
    gnupg2 \
    curl

RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list'


# RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
# RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list

RUN apt update
RUN apt upgrade

RUN apt-get install -y \
    gcc \
    libpq-dev \
    python3-dev \
    binutils \
    libproj-dev \
    gdal-bin \
    libgeos++ \
    proj-bin 


RUN apt-get install -y \
    postgis \
    postgresql-14-postgis-3 \
    postgresql-14-postgis-scripts \
    postgresql-contrib-14 \
    && rm -rf /var/lib/apt/lists/*

COPY Pipfile .
COPY Pipfile.lock .
RUN pipenv install --system

WORKDIR /app
RUN mkdir staticfiles
COPY . /app
RUN python3 manage.py collectstatic --noinput
RUN python3 manage.py makemigrations
RUN python3 manage.py migrate


# Creates a non-root user with an explicit UID and adds permission to access the /app folder
# For more info, please refer to https://aka.ms/vscode-docker-python-configure-containers
RUN adduser -u 5678 --disabled-password --gecos "" appuser && chown -R appuser /app
USER appuser

# During debugging, this entry point will be overridden. For more information, please refer to https://aka.ms/vscode-docker-python-debug
# CMD ["gunicorn", "--bind", "0.0.0.0:8000", "likemeapp.wsgi", "--reload"]
CMD [ "python3", "manage.py", "runserver" , "0.0.0.0:8000" ]
