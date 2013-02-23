###

node-ego
https://github.com/miniArray/node-ego

Copyright (c) 2013 Simon W. Jackson
Licensed under the MIT license.

###

jscrape = require 'jscrape' # lazy combo of jquery+jsdom+request
async = require 'async'
_ = require 'underscore'

domain = 'http://www.google.com' # maybe expand to other languages?

# returns the search URL for a query and page
searchUrl = (searchPhrase) ->
  # spaces=>+, otherwise escape
  regex = /\s/g
  searchPhrase = searchPhrase.replace regex, '+'
  searchPhrase = escape searchPhrase
  url = "#{domain}/search?hl=en&output=search&q=#{searchPhrase}&"
  # [no longer using pages this way, see below]
  # if (!isNaN(pageNum) && pageNum > 1) url += 'start=' + (10*pageNum) + '&'
  return url

module.exports.searchUrl = searchUrl

# given a search URL (for a single results page), request and parse results
getGoogleResultsPage = (url, callback) ->
  # (default 'Windows NT 6.0' probably looks fishy coming from a Linux server)
  jscrape.headers['User-Agent'] = 'Mozilla/5.0 (Macintosh Intel Mac OS X 10_7_4) AppleWebKit/536.5 (KHTML, like Gecko) Chrome/19.0.1084.52 Safari/536.5'

  jscrape(url, (error, $, response, body) ->
    if error
      return next error
    if !$
      return next(new Error "Missing jQuery object")

    # (highly unlikely)
    if response.statusCode isnt 200
        return next(new Error("Bad status code " + response.statusCode))

    results =
      nextPageUrl: null
      results: []

    # parse results
    $('#search ol li').each ->
      $vsc = $(this).find 'div.vsc'
      results.results.push
        title: $vsc.find('> h3 > a').text()
        url: $vsc.find('> div.s > .f > cite').text()
        description: $vsc.find('> div.s > .st').text()
        # page: pageNum,
        ranking: results.results.length + 1
    
    # parse the Next link
    nextPageUrl = $('#nav a#pnnext').attr 'href'
    if typeof nextPageUrl == 'undefined' or nextPageUrl is null || nextPageUrl is ''
      results.nextPageUrl = null

    # should be a relative url
    else if (/^http/.test(nextPageUrl))
      return callback(new Error("Next-page link is not in expected format"))

    else
      results.nextPageUrl = domain + nextPageUrl

    callback(null, results)
  )

# find where in the top 100 results a match is found.
# (only gets as many as needed, doesn't get 100 if found earlier)
# urlChecker:
#  - can be a string, then visible URL is indexOf'd w/ the string.
#  - can be a function, gets a result array (w/url, title, description), should return true on match.
# callback gets [error, result] where result contains page & ranking, or false if not found.
rank = (searchPhrase, urlChecker, callback) ->
  if typeof urlChecker is 'string'
    urlChecker = defaultUrlChecker urlChecker

  else if typeof urlChecker isnt 'function'
    throw new Error 'urlChecker needs to be a string or a function'
    
  pageNum = 1
  url = searchUrl searchPhrase    # initial
  found = false

  # get 10 pages of results. get the next-page url from the results of each.
  # (could just use start=N param, but seems more authentic to follow actual results link.
  #  also maybe less likely to raise red flags)
  `async.whilst(
    function test() { return pageNum <= 10 && url != null && !found },

    function getNextPage(next) {
      //console.log(pageNum, url)

      getGoogleResultsPage(url, function(error, pageResults){
        console.dir(pageResults)

        if (error) return next(error)

        // pageResults have 'nextPageUrl' (string) and results (array)
        url = pageResults.nextPageUrl || null
        
        for (var i=0; i<pageResults.results.length; i++) {
          if (urlChecker(pageResults.results[i]) === true) {
            found = pageResults.results[i]
            found.page = pageNum
            //console.log('Found!', found)
            return next()  // will stop b/c found is not falsy
          }
        }
        
        pageNum++
        next()
      })
    },
    function done(error) {
      if (error) return callback(error)
      callback(null, found)
    }
  )`

module.exports.rank = rank



# get 100 top results for a query
# searchPhrase: string to search for
# callback gets error or array of results
getGoogleResults = (searchPhrase, callback) ->
  pageNum = 1
  url = searchUrl searchPhrase
  results = []

  # get 10 pages of results. get the next-page url from the results of each.
  # (could just use start=N param, but seems more authentic to follow actual results link.
  #  also maybe less likely to raise red flags)
  `async.whilst(
    function test() { return pageNum <= 10 && url != null },

    function getNextPage(next) {
      //console.log(pageNum, url, results.length)
      
      getGoogleResultsPage(url, function(error, pageResults){
        console.dir(pageResults)
        
        if (error) return next(error)
        
        // pageResults have 'nextPageUrl' (string) and results (array)
        url = pageResults.nextPageUrl || null
        results = results.concat(pageResults.results)
        
        pageNum++
        next()
      })
    },
    function done(error) {
      if (error) return callback(error)
      callback(null, results)
    }
  )`

module.exports.getGoogleResults = getGoogleResults

# default urlChecker for a string match. returns a function.
defaultUrlChecker = (url) ->
  # Remove http://
  url = url.replace 'http://', ''

  return (result) ->
    if typeof result.url isnt 'undefined'
      if result.url.indexOf(url) isnt -1
        return true