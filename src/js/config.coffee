Settings = require('settings')

config =
  BASE_SERVER_URL: 'https://pebbleshows.herokuapp.com'
  TRAKT_CLIENT_ID: '16fc8c04f10ebdf6074611891c7ce2727b4fcae3d2ab2df177625989543085e9',

config.PEBBLE_CONFIG_URL = "#{config.BASE_SERVER_URL}/pebbleConfig"

module.exports = config;
