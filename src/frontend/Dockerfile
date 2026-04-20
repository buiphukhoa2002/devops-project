# Stage 1: Build React app
FROM node:18-alpine AS builder

WORKDIR /app

COPY package.json .
RUN npm install

COPY . .

ENV REACT_APP_API_URL=/api

RUN npm run build

# Stage 2: Serve with Nginx
FROM nginx:alpine

COPY --from=builder /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
