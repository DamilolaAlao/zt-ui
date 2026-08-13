# Host-side AudioEvent bridge for Ternary Bonsai.
FROM node:22-bookworm-slim

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY src ./src
COPY public ./public

ENV PORT=8090 \
    LLAMA_URL=http://llama:8080 \
    HOST=0.0.0.0

EXPOSE 8090
USER node
CMD ["npm", "start"]
