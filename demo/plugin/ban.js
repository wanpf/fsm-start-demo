(config =>

  pipy()

  .export('ban', {
    __isWhite: false,
    __port: 0,
  })

  .import({
    __turnDown: 'main',
  })
  
  .pipeline('request')
    .handleMessageStart(
      msg => (
        (downstream, path, blackObj, whiteObj, excludedPath) => (
            downstream = msg.head.headers['x-service-original-host'],
            console.log("downstream", downstream),
            downstream ? (
              blackObj = config.black.find(b => b.name == downstream),
              console.log("blackObj", blackObj),
              path = msg.head.path,
              blackObj ? (
                excludedPath = blackObj.excludedPaths.find(p => path.indexOf(p) > -1),
                console.log("excludedPath", excludedPath),
                excludedPath ? (
                  __isWhite = true
                ) : (
                  __turnDown = true
                )
              ) : (
                undefined
              )
            ) : (
              undefined
            ),

            console.log("__turnDown", __turnDown),
            (!__turnDown && downstream) ? (
              __port = msg.head.headers.host.indexOf(":") > -1 ? (
                msg.head.headers.host.split(":")[0]
              ) : (
                80
              ),
              // white list
              whiteObj = config.white.find(w => w.name == downstream),
              console.log("whiteObj", whiteObj),
              whiteObj ? (
                path = msg.head.path,
                excludedPath = whiteObj.excludedPaths.find(p => path.indexOf(p) > -1),
                console.log("excludedPath", excludedPath),
                excludedPath ? (
                  __turnDown = true
                ) : (
                  __isWhite = true
                )
              ) : (
                undefined
              )
            ) : (
              undefined
            )
        )
      )()
    )
    .link(
      'deny', () => __turnDown,
      'bypass'
    )
  
  .pipeline('deny')
    .replaceMessage(
      new Message({ status: 403, headers: {'content-type': 'application/json'} }, JSON.encode({message:'Access denied'}))
    )
  
  .pipeline('bypass')
  
  )(JSON.decode(pipy.load('config/inbound/ban.json')))