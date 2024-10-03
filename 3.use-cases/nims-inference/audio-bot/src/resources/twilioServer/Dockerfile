FROM --platform=linux/amd64 public.ecr.aws/docker/library/python:3.11

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends portaudio19-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 80

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "80"]