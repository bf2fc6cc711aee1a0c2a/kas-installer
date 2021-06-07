/*global module*/

const SECTION = 'application-services';
const FRONTEND_HOST = 'application-services-ui';
const FRONTEND_PORT = 80;
const routes = {};

routes[`/beta/${SECTION}`] = { host: `http://${FRONTEND_HOST}:${FRONTEND_PORT}` };
routes[`/${SECTION}`] = { host: `http://${FRONTEND_HOST}:${FRONTEND_PORT}` };
routes[`/beta/apps/${SECTION}`] = { host: `http://${FRONTEND_HOST}:${FRONTEND_PORT}` };
routes[`/apps/${SECTION}`] = { host: `http://${FRONTEND_HOST}:${FRONTEND_PORT}` };

bs = {
  //   port: 8089,
  ui: {
    port: 8089,
  },
  //   codeSync: false,
  //   https: false,
  host: 'pippo',
  proxy: 'https://localhost:8089',
  open: 'external',
  port: 9999,
};

module.exports = { routes, bs };
