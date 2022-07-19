FROM node:18-alpine

WORKDIR /app
ENV HOME=/app

COPY ./workspace/kas-ui /app
RUN npm ci

RUN mkdir -p   /app/dist /app/.npm /app/node_modules/.cache && \
    chmod 0777 /app/dist /app/.npm /app/node_modules/.cache

CMD [ "/bin/sh", "-c", "npx webpack serve --no-color --config webpack.dev.js --no-open" ]
