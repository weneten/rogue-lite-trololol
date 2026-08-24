FROM python:3.12-alpine
WORKDIR /app
RUN pip install --no-cache-dir "websockets>=12,<14"
COPY server.py .
EXPOSE 8765
CMD ["python", "-u", "server.py"]
