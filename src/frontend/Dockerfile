# Pre-built Dockerfile — run build.ps1 first to produce the dist/ folder locally.
# No npm install or build happens inside Docker.
FROM nginx:alpine
COPY dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
