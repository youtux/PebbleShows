var UI = require('ui');
var Settings = require('settings');
require('Object.observe.poly');

var CONFIG_BASE_URL = "http://bobby.alessiobogon.com:8020/";
var WATCHED_URL = "https://api-v2launch.trakt.tv/users/me/watched/shows";

var signInWindow;
var mainMenu;

/*
[{
  title: "abc",
  year: 2014,
  id: 1234
}, ...]
*/
var model = {
  watchedShows: undefined,
  toWatchList: undefined
}

var traktvRequest = function (method, url, body, callback) {
  var xhr = new XMLHttpRequest();
  body |= "";
  var accessToken = Settings.option('accessToken');
  xhr.open(method, url);
  xhr.setRequestHeader('Content-Type', 'application/json');
  xhr.setRequestHeader('trakt-api-version', '2');
  xhr.setRequestHeader('trakt-api-key', '16fc8c04f10ebdf6074611891c7ce2727b4fcae3d2ab2df177625989543085e9');
  if (accessToken){
    xhr.setRequestHeader('Authorization', 'Bearer ' + accessToken);
  }

  /*
  xhr.onreadystatechange = function () {
    console.log("Response for ", url);
    console.log('Status:', this.status);
    console.log('Headers:', this.getAllResponseHeaders());
    console.log('Body:', this.responseText);
  };
  */
  xhr.onload = function () {
    if (this.status != 200){
      console.log("Bad status: ", this.status);
    }
    if (this.status == 401){
      console.log("Authorization needed. Opening login window");
      displaySignInWindow();
      return;
    }
    callback(this.responseText, this.status);
  };
  xhr.send(JSON.stringify(body));
};

function getWatchedShows(callback){
  // TODO: use watchlist too
  traktvRequest('GET', WATCHED_URL, null, function(responseText) {
    var response = JSON.parse(responseText);
    callback(response.map(function(s){
      var show = s.show;
      return {
        title: show.title,
        year: show.year,
        id: show.ids.trakt
      };
    }));
  });
}

/*
[{
    "watched": false,
    "show": {...},
    "season": 1,
    "episode": 5,
  }, ...]
*/
function getToWatchList(callback){
  // TODO: use watchlist too
  var _toWatchList = [];
  var ajaxCallsRemaining = model.watchedShows.length;

  model.watchedShows.forEach(function(show){
    traktvRequest('GET', "https://api-v2launch.trakt.tv/shows/"+show.id+"/progress/watched", null, function(responseText, status){
      if (status != 200){
        ajaxCallsRemaining--;
        return;
      }
      var response = JSON.parse(responseText);
      console.log("Received data for show ", show.title);
      response.seasons.forEach(function(season){
        season.episodes.forEach(function(episode){
          if (! episode.completed){
            var ep={
              "watched": false,
              "show": show,
              "season": season.number,
              "episode": episode.number
            };
            _toWatchList.push(ep);
            //console.log(JSON.stringify(ep));
          }
        });
      });
      ajaxCallsRemaining--;
      if (ajaxCallsRemaining === 0){
        //console.log("seasonEpisodeNotWatched: ", JSON.stringify(episodeNotWatchedList));
        callback(_toWatchList);
      }
    });
  });
}


function displaySignInWindow(){
  signInWindow = new UI.Card({
    title: "Sign-in required",
    body: "Open the Pebble App and configure Pebble Shows."
  });
  signInWindow.on('click', 'back', function(){
    // No escape :)
  });
  signInWindow.show();
}

function refreshModels(){
  getWatchedShows(function(_watchedShows){
    model.watchedShows = _watchedShows;
    getToWatchList(function(_toWatchList){
      console.log("toWatchList updated");
      model.toWatchList = _toWatchList;
    });
  });
}

// Set a configurable with the open callback
Settings.config(
  {
    url: CONFIG_BASE_URL,
    autoSave: true
  },
  function(e) {
    console.log('closed configurable');
    console.log('e: ', JSON.stringify(e));
    signInWindow.hide();
    refreshModels();
  }
);


/*
// Show splash screen while waiting for data
var splashWindow = new UI.Card({
  title: 'Pebble Shows',
  icon: 'images/menu_icon.png',
  subtitle: 'The shows on your Pebble!',
  body: 'Connecting...'
});
splashWindow.show();
*/

var mainMenu = new UI.Menu({
  sections: [{
    items: [{
      title: 'To watch',
      id: 'toWatch'
    }, {
      title: 'Calendar',
      id: 'calendar'
    }]
  }]
});

function displayToWatchMenu(){
  var items = [];
  console.log("displayToWatchMenu: toWatchList: ", JSON.stringify(model.toWatchList));
  model.toWatchList.forEach(function(ep){
    items.push({
      title: ep.show.title,
      subtitle: "Season " + ep.season + " Ep. " + ep.episode,
      episode: ep
    });
  });
  console.log("obtained items: ", JSON.stringify(items));
  var toWatchMenu = new UI.Menu({
    sections: [{
      "items": items
    }]
  });
  toWatchMenu.on('longSelect', function(e){
    // TODO: mark as watched
  });
  toWatchMenu.on('select', function(e){
    var detailedItem = new UI.Card({
      title: "Details",
      subtitle: e.item.title,
      style: "small"
    });
    detailedItem.show();
  });
  toWatchMenu.show();
}

mainMenu.on('select', function(e) {
  console.log("select of ", JSON.stringify(e.item.id));
  if (e.item.id == "toWatch"){
    if (model.toWatchList !== undefined){
      displayToWatchMenu();
    }else{
      var observer = function(changes){
        if (changes.filter(function(c){return c.name == "toWatchList";}).length){
          console.log("called observe. this is ", JSON.stringify(this));
          displayToWatchMenu();
          Object.unobserve(model.toWatchList, observer);
        }
      };
      Object.observe(model, observer);
    }
  }else if(e.item.id == "calendar"){

  }
});
mainMenu.on('click', 'down', function(e) {
  console.log("mainMenu.on 'click', 'down'");
})
if (typeof PEBBLE_DEVELOPER !== 'undefined'){
  console.log("HI DEV!");
  var newSectionIndex = mainMenu.state.sections.length;
  mainMenu.items(newSectionIndex, [{title: "Developer tools", id: "developer"}]);
  mainMenu.on('select', function(e){
    if (e.item.id == "developer"){
      var devMenu = new UI.Menu({
        sections: [{
          items: [{
            title: "Reset localStorage",
            action: Settings.reset
          }, {
            title: "Init localStorage",
            action: Settings.init
          }, {
            title: "SAY MY NAME!",
            action: function(){console.log("YOU'RE HEISENBERG");}
          }]
        }]
      });
      devMenu.on('select', function(e){e.item.action()});
      devMenu.show();
    }
  });
}
mainMenu.show();

refreshModels();
