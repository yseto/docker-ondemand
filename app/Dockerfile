FROM perl:5.30-buster

RUN cpanm Carton \
    && mkdir -p /app
WORKDIR /app

COPY cpanfile* /app/
RUN carton install

COPY . /app
CMD ["carton", "exec", "--", "plackup", "-s", "Starlet", "--max-workers", "1"]
