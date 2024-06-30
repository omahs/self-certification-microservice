FROM rust:1.77-slim as casper-builder

RUN apt-get update && apt-get install -y build-essential pkg-config libssl-dev curl
RUN cargo install casper-client

FROM python:3.10-slim

WORKDIR /app
COPY --from=casper-builder /usr/local/cargo/bin/casper-client /usr/local/bin/casper-client
COPY . /app
RUN pip install --no-cache-dir -r requirements.txt
RUN apt-get update && apt-get install -y curl jq sed
EXPOSE 4000
CMD ["python", "app.py"]
