
config = require './config.json'
request = require 'request'
fs = require 'fs'
games = require './games.json'
async = require 'async'
util = require 'util'




###
  getHistory()

  Gets a chucks of history data for a game, based on a starting point in the history. Used
  recursively to get all history for a game since WF only allows 1500 moves per web service
  call.  
###
  
getHistory = (gid, start, num, callback) ->
  # In order to access WarFish, we need a valid "session" for a logged in user. 
  # This could be obtained programatically using a WarFish username/password. 
  # But here we use values obtained from the a client browser's cookies to
  # skip that step. Values are stored in `config.json` and were obtained from
  # Anthony's WF account. 

  cookiejar = request.jar()
  cookiejar.add request.cookie "SESSID=#{config.warfish.sessid}"
  cookiejar.add request.cookie "LAST=#{config.warfish.last}"

  params =
    gid: gid
    _format: "json"
    start: start 
    num: num

  page =
    url: config.warfish.historyapi
    jar: cookiejar
    qs: params

  request page, (err, resp, body) ->
    if err is null 
      try 
        history = JSON.parse body
      catch e
        console.log "Exception parsing WarFish JSON data for game id #{params.gid}, specifically #{e}"
        callback "Could not parse return JSON from WarFish for game id #{params.gid}", null if callback?
        return
      if history?.stat? and history.stat is 'ok' and history._content?.movelog?
        console.log "Got history from WarFish for Game ID: #{gid}"
        callback null, history._content.movelog
      else
        err = "WarFish returned error with data #{body}"
    if err isnt null
      console.log "Error occured: \n", err
      callback err, null if callback?

###
  processGameMoves()

  Recursively calls getHistory() to get a full game history. Callback is called when
  all data has been retrieved. The data resulted is an array of all moves for a game
###

processGameMoves = (gid, moves, start, callback) ->
  getHistory gid, start, "1000", (err, historygot) ->
    if err is null and historygot?._content?.m? is true
      moves = moves.concat historygot._content.m
      if historygot.total < (start + 1000)
        debugger
        console.log "Finished processing #{moves.length} of #{historygot.total}"
        callback null, moves
      else
        processGameMoves gid, moves, start + 1000, callback
    else
      console.log "Error occured: \n", err
      callback err or= "Error - no history data obtained", null


###
  matchSeatToProfileId()

  Since WarFish's history log uses a "seat id" to identify the attacking and defending players,
  we want to convert that to a "profile id" since that's uniquely identifies a player accross multiple games
  as the "seat id" is specific to a particular game.
###

matchSeatToProfileId = (gid, seat) ->
  for game in games
    if game.gid is gid
      for player in game.stats.players._content.players._content.player
        if player.id is seat
          return player.profileid
  return "-UNKNOWN-"

###
  classifyDiceRoll()

  Classifies an "attack" move. Other move types are igored.
###

classifyDiceRoll = (gid, move) ->
  # determine number of dice being rolled
  if move.a is 'a' # action == attack 
    if move.m isnt '' 
      console.log "Skipping move because dice are not 6-sided"
      return null
    roll = {}
    roll.gid = gid
    roll.moveid = move.id
    roll.numDiceDefend = Math.round (move.dd.length / 2)
    roll.numDiceAttack = Math.round (move.ad.length / 2)
    roll.attackerWins = Math.round move.dl
    roll.type = "#{roll.numDiceAttack}#{roll.numDiceDefend}#{roll.attackerWins}"
    roll.attackerId = matchSeatToProfileId gid, move.s
    roll.defenderId = matchSeatToProfileId gid, move.ds
    if roll?.numDiceDefend isnt 0 and roll?.numDiceAttack isnt 0 
      return roll
    else
      return null
  else
    return null


### 
   MAIN LOGIC 

   Go through a saved `games.json` file (loaded via a `require`) generated from
   "zoofish" project that calculates the "mElo" ratings.
###

computeResults = (allrolls) ->
  console.log "-----------------------------------------"
  sampleVsProbability =
    "111" : 
      count: 0
      oOdds: 15/36 
      tOdds: 0.417
    "110" : 
      count: 0
      oOdds: 21/36 
      tOdds: 0.583
    "121" : 
      count: 0
      oOdds: 55/216 
      tOdds: 0.254
    "120" : 
      count: 0
      oOdds: 161/216 
      tOdds: 0.746
    "211" : 
      count: 0
      oOdds: 125/216 
      tOdds: 0.578
    "210" : 
      count: 0
      oOdds: 91/216 
      tOdds: 0.422
    "222" : 
      count: 0
      oOdds: 295/1296 
      tOdds: 0.152
    "221" : 
      count: 0
      oOdds: 420/1296
      tOdds: 0.475
    "220" : 
      count: 0
      oOdds: 581/1296 
      tOdds: 0.373
    "311" : 
      count: 0
      oOdds: 855/1296 
      tOdds: 0.659
    "310" : 
      count: 0
      oOdds: 441/1296 
      tOdds: 0.341
    "322" : 
      count: 0
      oOdds: 2890/7776
      tOdds: 0.259
    "321" : 
      count: 0
      oOdds: 2611/7776 
      tOdds: 0.504
    "320" : 
      count: 0
      oOdds: 2275/7776
      tOdds: 0.237

  for roll in allrolls
    if roll?.type? and sampleVsProbability?[roll.type]?.count?
      sampleVsProbability[roll.type].count = 1 + sampleVsProbability[roll.type].count
    else
      console.log "Error roll count could not be computed for #{roll?.type}"


  console.log "sampleVsProbability = \n #{util.inspect sampleVsProbability, 3}"
  
  results =
    "1v1":
      "Count": sampleVsProbability["110"].count + sampleVsProbability["111"].count
    "1v2":
      "Count": sampleVsProbability["120"].count + sampleVsProbability["121"].count
    "2v1":
      "Count": sampleVsProbability["210"].count + sampleVsProbability["211"].count
    "2v2":
      "Count": sampleVsProbability["220"].count + sampleVsProbability["221"].count + sampleVsProbability["222"].count
    "3v1":
      "Count": sampleVsProbability["310"].count + sampleVsProbability["311"].count
    "3v2":
      "Count": sampleVsProbability["320"].count + sampleVsProbability["321"].count + sampleVsProbability["322"].count

  results["1v1"]["AttLose0"] = sampleVsProbability["111"].count / results["1v1"].Count 
  results["1v1"]["AttLose1"] = sampleVsProbability["110"].count / results["1v1"].Count
  results["1v1"]["ExpectedAttLose0"] = sampleVsProbability["111"].oOdds
  results["1v1"]["ExpectedAttLose1"] = sampleVsProbability["110"].oOdds
  results["1v1"]["DiffExpectedAttLose0"] = results["1v1"]["AttLose0"] - results["1v1"].ExpectedAttLose0
  results["1v1"]["DiffExpectedAttLose1"] = results["1v1"]["AttLose1"] - results["1v1"].ExpectedAttLose1
  results["1v2"]["AttLose0"] = sampleVsProbability["121"].count / results["1v2"].Count 
  results["1v2"]["AttLose1"] = sampleVsProbability["120"].count / results["1v2"].Count
  results["1v2"]["ExpectedAttLose0"] = sampleVsProbability["121"].oOdds
  results["1v2"]["ExpectedAttLose1"] = sampleVsProbability["120"].oOdds
  results["1v2"]["DiffExpectedAttLose0"] = results["1v2"]["AttLose0"] - results["1v2"].ExpectedAttLose0
  results["1v2"]["DiffExpectedAttLose1"] = results["1v2"]["AttLose1"] - results["1v2"].ExpectedAttLose1
  results["2v1"]["AttLose0"] = sampleVsProbability["211"].count / results["2v1"].Count
  results["2v1"]["AttLose1"] = sampleVsProbability["210"].count / results["2v1"].Count
  results["2v1"]["ExpectedAttLose0"] = sampleVsProbability["211"].oOdds
  results["2v1"]["ExpectedAttLose1"] = sampleVsProbability["210"].oOdds
  results["2v1"]["DiffExpectedAttLose0"] = results["2v1"]["AttLose0"] - results["2v1"].ExpectedAttLose0
  results["2v1"]["DiffExpectedAttLose1"] = results["2v1"]["AttLose1"] - results["2v1"].ExpectedAttLose1
  results["2v2"]["AttLose0"] = sampleVsProbability["222"].count / results["2v2"].Count
  results["2v2"]["AttLose1"] = sampleVsProbability["221"].count / results["2v2"].Count
  results["2v2"]["AttLose2"] = sampleVsProbability["220"].count / results["2v2"].Count
  results["2v2"]["ExpectedAttLose0"] = sampleVsProbability["222"].oOdds
  results["2v2"]["ExpectedAttLose1"] = sampleVsProbability["221"].oOdds
  results["2v2"]["ExpectedAttLose2"] = sampleVsProbability["220"].oOdds
  results["2v2"]["DiffExpectedAttLose0"] = results["2v2"]["AttLose0"] - results["2v2"].ExpectedAttLose0
  results["2v2"]["DiffExpectedAttLose1"] = results["2v2"]["AttLose1"] - results["2v2"].ExpectedAttLose1
  results["2v2"]["DiffExpectedAttLose2"] = results["2v2"]["AttLose2"] - results["2v2"].ExpectedAttLose2
  results["3v1"]["AttLose0"] = sampleVsProbability["311"].count / results["3v1"].Count
  results["3v1"]["AttLose1"] = sampleVsProbability["310"].count / results["3v1"].Count
  results["3v1"]["ExpectedAttLose0"] = sampleVsProbability["311"].oOdds
  results["3v1"]["ExpectedAttLose1"] = sampleVsProbability["310"].oOdds
  results["3v1"]["DiffExpectedAttLose0"] = results["3v1"]["AttLose0"] - results["3v1"].ExpectedAttLose0
  results["3v1"]["DiffExpectedAttLose1"] = results["3v1"]["AttLose1"] - results["3v1"].ExpectedAttLose1
  results["3v2"]["AttLose0"] = sampleVsProbability["322"].count / results["3v2"].Count
  results["3v2"]["AttLose1"] = sampleVsProbability["321"].count / results["3v2"].Count
  results["3v2"]["AttLose2"] = sampleVsProbability["320"].count / results["3v2"].Count
  results["3v2"]["ExpectedAttLose0"] = sampleVsProbability["322"].oOdds
  results["3v2"]["ExpectedAttLose1"] = sampleVsProbability["321"].oOdds
  results["3v2"]["ExpectedAttLose2"] = sampleVsProbability["320"].oOdds
  results["3v2"]["DiffExpectedAttLose0"] = results["3v2"]["AttLose0"] - results["3v2"].ExpectedAttLose0
  results["3v2"]["DiffExpectedAttLose1"] = results["3v2"]["AttLose1"] - results["3v2"].ExpectedAttLose1
  results["3v2"]["DiffExpectedAttLose2"] = results["3v2"]["AttLose2"] - results["3v2"].ExpectedAttLose2

  console.log results
  return results


main = () ->
  allrolls = []

  async.each games,
    (game, callback) ->
      console.log "Processing game #{game.gid}" 
      if game.teamsize isnt 1 
        console.log "Skipping team game for #{game.gid} - #{game.name}"
        callback null
        return        
      if game.details.rules._content.rules.adie isnt "6"
        console.log "Skipping game with non-standard attack dice sides (#{game.details.rules._content.rules.adie}) for #{game.gid} - #{game.name}"
        callback null
        return        
      if game.details.rules._content.rules.ddie isnt "6"
        console.log "Skipping game with non-standard defend dice sides (#{game.details.rules._content.rules.ddie}) for #{game.gid} - #{game.name}"
        callback null
        return        

      processGameMoves game.gid, [], 0, 
        (err, moves) ->
          gamerolls = []
          if err is null and moves?
            for move in moves 
              roll = classifyDiceRoll game.gid, move
              if roll? and roll isnt null
                console.log "Adding dice roll for #{roll.type} in #{game.gid}"
                gamerolls.push roll
            if gamerolls?.length? and gamerolls?.length? > 0
              allrolls = allrolls.concat gamerolls
          else
            console.log "Skipping processing moves in #{game.gid} since data was `null` or err was not `null`"
          callback null
          return
    ,
    (err) ->
      if err isnt null
        console.log "Error occured after processing all games: #{err}"
      console.log "Finished going through games. Generating `allrolls.json` with #{allrolls.length} records."
      fs.writeFile 'allrolls.json', JSON.stringify allrolls
      computeResults(allrolls)


debugger
allrollsjson = fs.readFileSync 'allrolls.json'
allrolls = JSON.parse allrollsjson
computeResults allrolls


# main()
