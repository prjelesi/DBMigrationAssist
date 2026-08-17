# Pre-built Dockerfile — run build.ps1 first to produce the dist/ folder locally.
# No npm install or build happens inside Docker.
FROM nginx:alpine
COPY dist /usr/share/nginx/html
ENV API_UPSTREAM=http://api:8080 \
	NGINX_ENVSUBST_FILTER=^API_UPSTREAM$
COPY nginx.conf /etc/nginx/templates/default.conf.template
EXPOSE 80
