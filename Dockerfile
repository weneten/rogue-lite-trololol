# syntax=docker/dockerfile:1

FROM barichello/godot-ci:4.7 AS builder
WORKDIR /project
COPY . .
RUN mkdir -p build/web \
    && godot --headless --import --quit \
    && godot --headless --export-release "Web" build/web/index.html

FROM nginx:alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /project/build/web /usr/share/nginx/html
EXPOSE 80
