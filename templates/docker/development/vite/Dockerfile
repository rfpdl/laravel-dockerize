FROM node:20-alpine
WORKDIR /var/www
COPY package*.json ./
# Use npm ci when a lockfile exists, otherwise fallback to npm install
RUN if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then \
      npm ci; \
    else \
      npm install; \
    fi
COPY . .
EXPOSE 5173
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0", "--port", "5173"]
