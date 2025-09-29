# Stage 1: Build assets
FROM node:20-alpine AS builder
WORKDIR /var/www
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Nginx production image
FROM nginx:alpine
COPY ./docker/production/nginx/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /var/www/public /var/www/public
WORKDIR /var/www/public
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
