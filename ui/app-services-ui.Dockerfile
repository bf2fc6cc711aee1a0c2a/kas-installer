FROM node:18-alpine

WORKDIR /app
ENV HOME=/app PROXY_USE_AGENT=false

COPY ./workspace/app-services-ui /app
RUN npm ci
RUN apk add git

RUN mkdir -p   /app/dist /app/.npm /app/node_modules/.cache /app/node_modules/@redhat-cloud-services/frontend-components-config-utilities/repos && \
    chmod 0777 /app/dist /app/.npm /app/node_modules/.cache /app/node_modules/@redhat-cloud-services/frontend-components-config-utilities/repos

CMD [ "/bin/sh", "-c", "npm run start:dev" ]
