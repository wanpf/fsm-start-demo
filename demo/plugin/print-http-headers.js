(config => (

  pipy({
  })

    .pipeline()

    // request
    .handleMessageStart(
      msg => (
        !config?.skip_domains?.find(
          domain => domain == msg?.head?.headers.host,
          true
        ) && (
          console.log('==============[HeaderFilter plugin] http request headers:', msg.head.headers)
        )
      )
    )

    .chain()

    // response
    .handleMessageStart(
      msg => (
        console.log('==============[HeaderFilter plugin] http response headers:', msg.head.headers)
      )
    )

))(JSON.decode(pipy.load('plugins/test/header-filter/domain.json')))